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
    // The file and SQLite storages below share this folder; `exercise` clears the UserDefaults suite itself
    let folder = try DefaultFileLocator().directory(for: .app(.temporary, namespace: .directory(named: id)))
    defer {
        try? FileManager.default.removeItem(at: folder)
    }
    
    // Coders
    for coder in [JSONDataCoder() as DataCoder, PropertyListDataCoder(), RawDataCoder(), RawDataCoder(fallback: PropertyListDataCoder())] {
        let decoded: Int = try await coder.decode(coder.encode(42))
        XCTAssertEqual(decoded, 42, "\(type(of: coder)) from \(context)")
    }
    
    // Every storage, directly and through the coding and observation layers. The keychain and the iCloud key-value store
    // need entitlements that test bundles can't have, so those storages use in-memory backing storages
    try await exercise(InMemoryStorage(scope: .app(namespace: .bucket(named: id))), key: "key", context: context)
    try await exercise(UserDefaultsStorage(scope: .app(.suite(named: id))), key: "key", context: context)
    try await exercise(FileStorage(scope: .app(.temporary, namespace: .directory(named: id))), key: .init(name: "key"), context: context)
    try await exercise(SQLiteStorage(scope: .app(.temporary, namespace: .directory(named: id))), key: "key", context: context)
    try await exercise(KeychainStorage(scope: .app(namespace: .service(named: id)), backingStore: InMemoryKeychain(), locator: DefaultKeychainLocator()),
                       key: .init(name: "key"), context: context)
    if #available(watchOS 9.0, *) {
        try await exercise(UbiquitousStorage(scope: .shared(namespace: .keyPrefix(named: id)), backingStore: InMemoryUbiquitousStore(), locator: DefaultUbiquitousLocator()),
                           key: "key", context: context)
    }

    // Unified storage
    let storage = UnifiedStorage(factory: ObservableUnifiedStorageFactory())
    let key = InMemoryKey<Int>(key: "unified", scope: .app(namespace: .bucket(named: id)))
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
    try await storage.clear(storage: InMemoryStorage.self, forScope: .app(namespace: .bucket(named: id)))
    let firstStreamed = await streamed.value
    
    XCTAssertEqual(fetched, 1, "UnifiedStorage from \(context)")
    XCTAssertEqual(firstStreamed, 1, "UnifiedStorage stream from \(context)")
    XCTAssertEqual(published.all, [nil, 1, nil, 2, nil, nil], "UnifiedStorage publisher from \(context)")
    subscription?.cancel()
}

private func exercise<Storage: KeyValueDataStorage>(_ storage: Storage, key: Storage.Key, context: String,
                                                    isolation: isolated (any Actor)? = #isolation) async throws {
    let description = "\(Storage.self) from \(context)"
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
    
    // Coding and observation, which read the storage's scope on CodingStorageActor
    let observable = KeyValueObservableStorage(storage: storage, coder: RawDataCoder())
    let codingKey = KeyValueCodingStorageKey<Storage, Int>(key: key)
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
