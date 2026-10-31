//
//  IsolationTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 15.10.26.
//

import XCTest
import Foundation
import Combine
import KeyValueStorage // intentionally not @testable: calls the API like clients do

/// Calls every public API from different isolation contexts, so each Swift version's runtime isolation checks
/// run for every entry point. Swift 6.0, for example, crashed when a storage's `scope` was read outside its actor.
final class IsolationTests: XCTestCase {
    func testNonisolated() async throws {
        try await exerciseAPI(context: "nonisolated")
    }
    
    @MainActor
    func testMainActor() async throws {
        try await exerciseAPI(context: "MainActor")
    }
    
    func testCustomActor() async throws {
        try await Caller().run()
    }
    
    @CodingStorageActor
    func testCodingStorageActor() async throws {
        try await exerciseAPI(context: "CodingStorageActor")
    }
}

// MARK: - Helpers

private actor Caller {
    func run() async throws {
        try await exerciseAPI(context: "custom actor")
    }
}

/// Runs on the caller's actor, so every call below is made from that context.
private func exerciseAPI(context: String, isolation: isolated (any Actor)? = #isolation) async throws {
    let id = "isolation-\(UUID().uuidString)"
    // The file and SQLite storages below share this namespace's folder; `exercise` clears the UserDefaults namespace itself
    let folder = try DefaultFileLocator().directory(for: .own(.temporary, namespace: .init(id))).deletingLastPathComponent()
    defer {
        try? FileManager.default.removeItem(at: folder)
    }
    
    // Coders
    for coder in [JSONDataCoder() as DataCoder, PropertyListDataCoder(), RawDataCoder(), RawDataCoder(fallback: PropertyListDataCoder())] {
        let decoded: Int = try coder.decode(coder.encode(42))
        XCTAssertEqual(decoded, 42, "\(type(of: coder)) from \(context)")
    }
    
    // Every storage, directly and through the coding and observation layers. The keychain and the iCloud key-value store
    // need entitlements that test bundles can't have, so those storages use in-memory backing storages
    try await exercise(InMemoryStorage(scope: .own(namespace: .init(id))), key: "key", context: context)
    try await exercise(UserDefaultsStorage(scope: .own(namespace: .init(id))), key: "key", context: context)
    try await exercise(FileStorage(scope: .own(.temporary, namespace: .init(id))), key: "key", context: context)
    try await exercise(SQLiteStorage(scope: .own(.temporary, namespace: .init(id))), key: "key", context: context)
    try await exercise(KeychainStorage(scope: .own(namespace: .init(id)), backingStore: InMemoryKeychain(), locator: DefaultKeychainLocator()),
                       key: "key", context: context)
    if #available(watchOS 9.0, *) {
        try await exercise(UbiquitousStorage(scope: .iCloud(.own, namespace: .init(id)), backingStore: InMemoryUbiquitousStore(), locator: DefaultUbiquitousLocator()),
                           key: "key", context: context)
    }

    // An isolated storage, directly (no `try`: it keeps `InMemoryStorage`'s `Never`) and through the async coding storage
    let isolated = IsolatedInMemoryStorage(InMemoryStorage(scope: .own(namespace: .init("\(id)-isolated"))))
    await isolated.save(Data([1]), forKey: "key")
    let isolatedFetched = await isolated.fetch(forKey: "key")
    await isolated.set(nil, forKey: "key")
    let isolatedCoding = AsyncKeyValueCodingStorage(storage: isolated)
    try await isolatedCoding.save(7, forKey: KeyValueCodingStorageKey(key: "coded"))
    let isolatedDecoded: Int? = try await isolatedCoding.fetch(forKey: KeyValueCodingStorageKey(key: "coded"))
    await isolated.clear()
    XCTAssertEqual(isolatedFetched, Data([1]), "IsolatedKeyValueDataStorage from \(context)")
    XCTAssertEqual(isolatedDecoded, 7, "IsolatedKeyValueDataStorage coding from \(context)")
    XCTAssertEqual(isolated.scope, .own(namespace: .init("\(id)-isolated")), "IsolatedKeyValueDataStorage scope from \(context)")

    // Unified storage
    let storage = UnifiedStorage(factory: ObservableUnifiedStorageFactory())
    let key = InMemoryKey<Int>(key: "unified", scope: .own(namespace: .init(id)))
    let published = Values<Int?>()
    let subscription = try await storage.publisher(forKey: key)?.sink { published.append($0) }
    let stream = try await storage.stream(forKey: key, includingCurrentValue: false)
    let streamed = Task { () -> Int?? in
        guard let stream else { return nil }
        for await value in stream { return value }
        return nil
    }
    
    try await storage.save(1, forKey: key)
    let fetched = try await storage.fetch(forKey: key)
    try await storage.set(nil, forKey: key)
    try await storage.set(2, forKey: key)
    try await storage.delete(forKey: key)
    try await storage.clear(storage: IsolatedInMemoryStorage.self, forScope: .own(namespace: .init(id)))
    let firstStreamed = await streamed.value
    
    XCTAssertEqual(fetched, 1, "UnifiedStorage from \(context)")
    XCTAssertEqual(firstStreamed, 1, "UnifiedStorage stream from \(context)")
    XCTAssertEqual(published.all, [nil, 1, nil, 2, nil, nil], "UnifiedStorage publisher from \(context)")
    subscription?.cancel()
}

private func exercise<Storage: KeyValueDataStorage>(_ storage: sending Storage, key: Storage.Key, context: String,
                                                    isolation: isolated (any Actor)? = #isolation) async throws {
    let description = "\(Storage.self) from \(context)"
    try exerciseSynchronously(storage, key: key, description: description)

    // Async coding and observation, which reach the storage from CodingStorageActor, so through the isolated wrapper
    let observable = KeyValueObservableStorage(storage: IsolatedKeyValueDataStorage(storage), coder: RawDataCoder())
    let codingKey = KeyValueCodingStorageKey<IsolatedKeyValueDataStorage<Storage>, Int>(key: key)
    let published = Values<Int?>()
    let subscription = try await observable.publisher(forKey: codingKey).sink { published.append($0) }
    let stream = try await observable.stream(forKey: codingKey, includingCurrentValue: false)
    let streamed = Task { () -> Int?? in
        for await value in stream { return value }
        return nil
    }
    
    try await observable.save(1, forKey: codingKey)
    let fetched = try await observable.fetch(forKey: codingKey)
    try await observable.set(nil, forKey: codingKey)
    try await observable.clear()
    let firstStreamed = await streamed.value
    
    XCTAssertEqual(fetched, 1, description)
    XCTAssertEqual(firstStreamed, 1, description)
    XCTAssertEqual(published.all, [nil, 1, nil, nil], description)
    subscription.cancel()
}

/// The data and coding storages without `await`: a synchronous storage stays synchronous in generic code too.
/// - Note: Synchronous on purpose: inside `async` code, the same calls would resolve to the `async` requirements.
private func exerciseSynchronously<Storage: KeyValueDataStorage>(_ storage: Storage, key: Storage.Key, description: String) throws {
    let data = Data([1, 2, 3])
    
    // Data storage
    _ = storage.scope
    try storage.save(data, forKey: key)
    let saved = try storage.fetch(forKey: key)
    try storage.set(nil, forKey: key)
    let setToNil = try storage.fetch(forKey: key)
    try storage.set(data, forKey: key)
    try storage.delete(forKey: key)
    let deleted = try storage.fetch(forKey: key)
    try storage.save(data, forKey: key)
    try storage.clear()
    let cleared = try storage.fetch(forKey: key)
    
    XCTAssertEqual(saved, data, description)
    XCTAssertNil(setToNil, description)
    XCTAssertNil(deleted, description)
    XCTAssertNil(cleared, description)

    // Coding storage
    let coding = KeyValueCodingStorage(storage: storage)
    let codingKey = KeyValueCodingStorageKey<Storage, Int>(key: key)
    try coding.save(1, forKey: codingKey)
    let fetched = try coding.fetch(forKey: codingKey)
    try coding.set(nil, forKey: codingKey)
    let afterSet = try coding.fetch(forKey: codingKey)
    try coding.save(2, forKey: codingKey)
    try coding.clear()
    let afterClear = try coding.fetch(forKey: codingKey)

    XCTAssertEqual(fetched, 1, description)
    XCTAssertNil(afterSet, description)
    XCTAssertNil(afterClear, description)
}

/// Collects values delivered on any thread.
private final class Values<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values = [Value]()
    
    var all: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
    
    func append(_ value: Value) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }
}
