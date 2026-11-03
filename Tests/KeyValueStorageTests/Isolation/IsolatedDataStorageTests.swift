//
//  IsolatedDataStorageTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class IsolatedDataStorageTests: XCTestCase {
    private let error = MockError(id: 1)

    // MARK: Forwarding

    func testOperationsReachTheWrappedStorage() async throws {
        // Given
        let (storage, log) = makeStorage()

        // When
        try await storage.save(Data([1]), forKey: "key")
        let fetched = try await storage.fetch(forKey: "key")
        try await storage.set(nil, forKey: "key")
        try await storage.set(Data([2]), forKey: "other")
        try await storage.delete(forKey: "other")
        try await storage.clear()

        // Then
        XCTAssertEqual(fetched, Data([1]))
        XCTAssertEqual(log.calls, [.save(Data([1]), "key"), .fetch("key"), .delete("key"), .save(Data([2]), "other"), .delete("other"), .clear])
    }

    func testTheWrappedStoragesErrorsPassThrough() async {
        // Given
        let (storage, log) = makeStorage()
        log.fail(with: error)

        // When - Then
        await assertThrows(error) { try await storage.fetch(forKey: "key") }
        await assertThrows(error) { try await storage.save(Data(), forKey: "key") }
        await assertThrows(error) { try await storage.set(nil, forKey: "key") }
        await assertThrows(error) { try await storage.delete(forKey: "key") }
        await assertThrows(error) { try await storage.clear() }
    }

    // MARK: Scope and Creation

    func testScopeIsTheWrappedStoragesWithoutAwait() {
        let (storage, log) = makeStorage()
        XCTAssertEqual(storage.scope, log.scope)
    }

    func testInitWithAScopeCreatesTheWrappedStorage() async throws {
        // Given
        let scope = MockScope(name: "created-\(UUID().uuidString)")

        // When
        let storage = try await IsolatedDataStorage<LoggedStorage>(scope: scope)
        try await storage.save(Data([1]), forKey: "key")

        // Then: the wrapped storage has the scope, and gets the calls
        XCTAssertEqual(storage.scope, scope)
        XCTAssertEqual(Log.named(scope.name).calls, [.save(Data([1]), "key")])
    }

    // MARK: Isolation

    func testOperationsNeverOverlap() async throws {
        // Given
        let running = RunningCalls()
        let storage = IsolatedDataStorage(OverlapDetectingStorage(running: running))

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
        XCTAssertEqual(running.maximum, 1)
    }

    // MARK: Coding

    func testTheCodingStorageWorksOnTop() async throws {
        // Given
        let coding = AsyncCodingStorage(storage: makeStorage().storage, coder: DataCoderMock())
        let key = CodingStorageKey<IsolatedDataStorage<LoggedStorage>, Int>(key: "key")

        // When
        try await coding.save(42, forKey: key)

        // Then
        let value = try await coding.fetch(forKey: key)
        XCTAssertEqual(value, 42)
    }

    // MARK: Helpers

    /// An isolated storage of a scope of its own, and the log its wrapped storage records into.
    private func makeStorage() -> (storage: IsolatedDataStorage<LoggedStorage>, log: Log) {
        let scope = MockScope(name: "isolated-\(UUID().uuidString)")
        return (IsolatedDataStorage(LoggedStorage(scope: scope)), Log.named(scope.name))
    }
}

// MARK: - LoggedStorage

/// A synchronous storage that isn't `Sendable`, as `IsolatedDataStorage` wraps; records into the `Log` named like its scope,
/// since the caller gives the storage up.
private final class LoggedStorage: DataStorage {
    typealias Key = String
    typealias Error = MockError

    let scope: MockScope
    private var values = [String: Data]()

    init(scope: MockScope) {
        self.scope = scope
    }

    func fetch(forKey key: String) throws(MockError) -> Data? {
        try Log.named(scope.name).record(.fetch(key))
        return values[key]
    }

    func save(_ value: Data, forKey key: String) throws(MockError) {
        try Log.named(scope.name).record(.save(value, key))
        values[key] = value
    }

    func delete(forKey key: String) throws(MockError) {
        try Log.named(scope.name).record(.delete(key))
        values[key] = nil
    }

    func clear() throws(MockError) {
        try Log.named(scope.name).record(.clear)
        values = [:]
    }
}

// MARK: - Log

/// A `LoggedStorage`'s calls, and the error it throws instead of answering, by scope name.
private final class Log: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var logs = [String: Log]()

    let scope: MockScope
    private let lock = NSLock()
    private var recorded = [DataStorageCall]()
    private var error: MockError?

    private init(scope: MockScope) {
        self.scope = scope
    }

    static func named(_ name: String) -> Log {
        lock.withLock {
            if let log = logs[name] {
                return log
            }

            let log = Log(scope: MockScope(name: name))
            logs[name] = log
            return log
        }
    }

    var calls: [DataStorageCall] {
        lock.withLock { recorded }
    }

    func fail(with error: MockError) {
        lock.withLock { self.error = error }
    }

    func record(_ call: DataStorageCall) throws(MockError) {
        let error = lock.withLock {
            recorded.append(call)
            return self.error
        }

        if let error {
            throw error
        }
    }
}

// MARK: - RunningCalls

/// Counts the calls in progress at once, from any thread.
private final class RunningCalls: @unchecked Sendable {
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
private final class OverlapDetectingStorage: DataStorage {
    typealias Key = String
    typealias Error = MockError

    let scope = MockScope(name: "overlap")
    private let running: RunningCalls
    private var value: Data?

    init(running: RunningCalls) {
        self.running = running
    }

    init(scope: MockScope) {
        self.running = RunningCalls()
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
        running.enter()
        defer { running.leave() }
        usleep(100)
        return body()
    }
}
