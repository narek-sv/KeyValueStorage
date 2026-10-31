//
//  IsolatedKeyValueDataStorageTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class IsolatedKeyValueDataStorageTests: XCTestCase {
    private let error = MockError(id: 1)

    // MARK: Forwarding

    func testOperationsReachTheWrappedStorage() async throws {
        // Given
        let storage = makeStorage()

        // When
        try await storage.save(Data([1]), forKey: "key")
        let fetched = try await storage.fetch(forKey: "key")
        try await storage.set(nil, forKey: "key")
        try await storage.set(Data([2]), forKey: "other")
        try await storage.delete(forKey: "other")
        try await storage.clear()

        // Then
        XCTAssertEqual(fetched, Data([1]))
        let calls = await storage.withStorage { $0.calls }
        XCTAssertEqual(calls, [.save(Data([1]), "key"), .fetch("key"), .delete("key"), .save(Data([2]), "other"), .delete("other"), .clear])
    }

    func testTheWrappedStoragesErrorsPassThrough() async {
        // Given
        let storage = makeStorage()
        let error = error
        await storage.withStorage { $0.error = error }

        // When - Then
        await assertThrows(error) { try await storage.fetch(forKey: "key") }
        await assertThrows(error) { try await storage.save(Data(), forKey: "key") }
        await assertThrows(error) { try await storage.set(nil, forKey: "key") }
        await assertThrows(error) { try await storage.delete(forKey: "key") }
        await assertThrows(error) { try await storage.clear() }
    }

    // MARK: Scope and Creation

    func testScopeIsTheWrappedStoragesWithoutAwait() {
        XCTAssertEqual(makeStorage().scope, MockScope(name: "isolated"))
    }

    func testInitWithAScopeCreatesTheWrappedStorage() async throws {
        // When
        let storage = try await IsolatedKeyValueDataStorage<DataStorageMock>(scope: .init(name: "created"))

        // Then
        XCTAssertEqual(storage.scope, MockScope(name: "created"))
        let wrappedScope = await storage.withStorage { $0.scope }
        XCTAssertEqual(wrappedScope, MockScope(name: "created"))
    }

    // MARK: Isolation

    func testWithStorageIsOneAtomicStep() async throws {
        // Given
        let storage = makeStorage()
        let increments = 1_000

        // When: concurrent read-increment-writes
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<increments {
                group.addTask {
                    await storage.withStorage { wrapped in
                        let count = wrapped.values["count"].map { Int($0[0]) + Int($0[1]) * 256 } ?? 0
                        wrapped.values["count"] = Data([UInt8((count + 1) % 256), UInt8((count + 1) / 256)])
                    }
                }
            }
        }

        // Then
        let count = await storage.withStorage { $0.values["count"].map { Int($0[0]) + Int($0[1]) * 256 } }
        XCTAssertEqual(count, increments)
    }

    func testOperationsNeverOverlap() async throws {
        // Given
        let entries = Entries()
        let storage = IsolatedKeyValueDataStorage(OverlapDetectingStorage(entries: entries))

        // When: every operation, from many tasks at once
        try await withThrowingTaskGroup(of: Void.self) { group in
            for task in 0..<100 {
                group.addTask {
                    try await storage.save(Data([UInt8(task)]), forKey: "key")
                    _ = try await storage.fetch(forKey: "key")
                    try await storage.set(nil, forKey: "key")
                    try await storage.delete(forKey: "key")
                    try await storage.clear()
                }
            }
            try await group.waitForAll()
        }

        // Then
        XCTAssertEqual(entries.maximum, 1)
    }

    // MARK: Coding

    func testTheCodingStorageWorksOnTop() async throws {
        // Given
        let coding = AsyncKeyValueCodingStorage(storage: makeStorage(), coder: DataCoderMock())
        let key = KeyValueCodingStorageKey<IsolatedKeyValueDataStorage<DataStorageMock>, Int>(key: "key")

        // When
        try await coding.save(42, forKey: key)

        // Then
        let value = try await coding.fetch(forKey: key)
        XCTAssertEqual(value, 42)
    }

    // MARK: Helpers

    private func makeStorage() -> IsolatedKeyValueDataStorage<DataStorageMock> {
        IsolatedKeyValueDataStorage(DataStorageMock(scope: .init(name: "isolated")))
    }
}

// MARK: - Entries

/// Counts the calls in progress at once, from any thread.
private final class Entries: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private var highest = 0

    var maximum: Int {
        lock.withLock { highest }
    }

    func enter() {
        lock.withLock {
            current += 1
            highest = max(highest, current)
        }
    }

    func leave() {
        lock.withLock { current -= 1 }
    }
}

// MARK: - OverlapDetectingStorage

/// Stays in every call for a moment, so calls that overlap are counted.
private final class OverlapDetectingStorage: KeyValueDataStorage {
    typealias Key = String
    typealias Error = MockError

    let scope = MockScope(name: "overlap")
    private let entries: Entries
    private var value: Data?

    init(entries: Entries) {
        self.entries = entries
    }

    init(scope: MockScope) {
        self.entries = Entries()
    }

    func fetch(forKey key: String) throws(MockError) -> Data? {
        call { value }
    }

    func save(_ value: Data, forKey key: String) throws(MockError) {
        call { self.value = value }
    }

    func delete(forKey key: String) throws(MockError) {
        call { value = nil }
    }

    func clear() throws(MockError) {
        call { value = nil }
    }

    private func call<T>(_ body: () -> T) -> T {
        entries.enter()
        defer { entries.leave() }
        usleep(100)
        return body()
    }
}
