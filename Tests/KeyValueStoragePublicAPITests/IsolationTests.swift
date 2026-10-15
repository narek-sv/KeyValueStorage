//
//  IsolationTests.swift
//
//
//  Created by Narek Sahakyan on 15.10.26.
//

import XCTest
import Foundation
import Combine
import KeyValueStorage // intentionally not @testable: calls the API like clients do

/// Calls every public API from different isolation contexts, so each Swift version's runtime isolation checks
/// run for every entry point. Swift 6.0, for example, crashed when a storage's `domain` was read outside its actor.
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
    
    @InMemoryActor
    func testInMemoryActor() async throws {
        try await exerciseAPI(context: "InMemoryActor")
    }
    
    @UserDefaultsActor
    func testUserDefaultsActor() async throws {
        try await exerciseAPI(context: "UserDefaultsActor")
    }
    
    @FileActor
    func testFileActor() async throws {
        try await exerciseAPI(context: "FileActor")
    }
    
    @SQLiteActor
    func testSQLiteActor() async throws {
        try await exerciseAPI(context: "SQLiteActor")
    }
    
    @KeychainActor
    func testKeychainActor() async throws {
        try await exerciseAPI(context: "KeychainActor")
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
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(id, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
        UserDefaults().removePersistentDomain(forName: id)
    }
    
    // Coders
    for coder in [JSONDataCoder() as DataCoder, PropertyListDataCoder(), RawDataCoder(), RawDataCoder(fallback: PropertyListDataCoder())] {
        let decoded: Int = try await coder.decode(coder.encode(42))
        XCTAssertEqual(decoded, 42, "\(type(of: coder)) from \(context)")
    }
    
    // Every storage, directly and through the coding and observation layers
    try await exercise(await InMemoryStorage(domain: id), key: "key", context: context)
    try await exercise(try await UserDefaultsStorage(domain: id), key: "key", context: context)
    try await exercise(await FileStorage(fileManager: .default, root: root.appendingPathComponent("Files")), key: "key", context: context)
    try await exercise(try await SQLiteStorage(fileManager: .default, root: root.appendingPathComponent("SQLite")), key: "key", context: context)
    try await exercise(await KeychainStorage(keychain: InMemoryKeychain(serviceName: id)), key: .init(name: "key"), context: context)
    
    // Unified storage
    let storage = UnifiedStorage(factory: ObservableUnifiedStorageFactory())
    let key = InMemoryKey<Int>(key: "unified", domain: id)
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
    try await storage.clear(storage: InMemoryStorage.self, forDomain: id)
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
    _ = storage.domain
    try await storage.save(data, forKey: key)
    let saved = try await storage.fetch(forKey: key)
    try await storage.set(nil, forKey: key)
    let setToNil = try await storage.fetch(forKey: key)
    try await storage.set(data, forKey: key)
    try await storage.delete(forKey: key)
    let deleted = try await storage.fetch(forKey: key)
    try await storage.save(data, forKey: key)
    try await storage.clear()
    let cleared = try await storage.fetch(forKey: key)
    
    XCTAssertEqual(saved, data, description)
    XCTAssertNil(setToNil, description)
    XCTAssertNil(deleted, description)
    XCTAssertNil(cleared, description)
    
    // Coding and observation, which read the storage's domain on CodingStorageActor
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

/// Keeps items in memory, because the real keychain needs entitlements that test bundles can't have.
private final class InMemoryKeychain: KeychainWrapper, @unchecked Sendable {
    private let lock = NSLock()
    private var items = [String: Data]()
    
    override func get(forKey key: String, isSynchronizable: Bool = false) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return items[key]
    }
    
    override func set(_ value: Data, forKey key: String, withAccessibility accessibility: KeychainAccessibility? = nil, isSynchronizable: Bool = false) throws {
        lock.lock()
        defer { lock.unlock() }
        items[key] = value
    }
    
    override func remove(forKey key: String, isSynchronizable: Bool = false) throws {
        lock.lock()
        defer { lock.unlock() }
        items[key] = nil
    }
    
    override func removeAll() throws {
        lock.lock()
        defer { lock.unlock() }
        items.removeAll()
    }
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
