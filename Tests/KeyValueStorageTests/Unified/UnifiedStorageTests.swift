//
//  UnifiedStorageTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class UnifiedStorageTests: XCTestCase {
    private typealias Key<Value: CodingValue> = UnifiedStorageKey<AsyncDataStorageMock, Value>

    private let error = MockError(id: 1)

    // MARK: Storage Per Type and Scope

    func testOneStoragePerTypeAndScope() async throws {
        // Given
        let factory = RecordingFactory()
        let storage = UnifiedStorage(factory: factory)

        // When: repeated operations, and the default scope given and omitted
        try await storage.save(1, forKey: Key<Int>(key: "a"))
        _ = try await storage.fetch(forKey: Key<Int>(key: "a", scope: .default))
        try await storage.delete(forKey: Key<Int>(key: "b"))
        try await storage.clear(storage: AsyncDataStorageMock.self)

        // Then
        XCTAssertEqual(factory.dataStorageCalls, 1)
        XCTAssertEqual(factory.codingStorageCalls, 1)
    }

    func testScopesAndStorageTypesHaveStoragesOfTheirOwn() async throws {
        // Given
        let factory = RecordingFactory()
        let storage = UnifiedStorage(factory: factory)

        // When
        try await storage.save(1, forKey: Key<Int>(key: "key", scope: .init(name: "first")))
        try await storage.save(2, forKey: Key<Int>(key: "key", scope: .init(name: "second")))
        try await storage.save(3, forKey: UnifiedStorageKey<GatedStorage, Int>(key: "key"))

        // Then
        XCTAssertEqual(factory.dataStorageCalls, 3)
        let first = try await storage.fetch(forKey: Key<Int>(key: "key", scope: .init(name: "first")))
        let second = try await storage.fetch(forKey: Key<Int>(key: "key", scope: .init(name: "second")))
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2)
    }

    func testConcurrentFirstCallsCreateOneStorage() async throws {
        // Given
        let factory = RecordingFactory()
        let storage = UnifiedStorage(factory: factory)

        // When
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    try await storage.save(index, forKey: Key<Int>(key: .init("key\(index)")))
                }
            }
            try await group.waitForAll()
        }

        // Then
        XCTAssertEqual(factory.dataStorageCalls, 1)
        XCTAssertEqual(factory.codingStorageCalls, 1)
    }

    func testAFailedCreationIsReportedAndRetried() async throws {
        // Given
        let factory = RecordingFactory(failures: 1)
        let storage = UnifiedStorage(factory: factory)
        let key = Key<Int>(key: "key")

        // When - Then
        await assertThrows(KeyValueCodingError<AsyncDataStorageMock>.storage(RecordingFactory.creationError)) {
            try await storage.save(1, forKey: key)
        }
        try await storage.save(1, forKey: key)
        let value = try await storage.fetch(forKey: key)
        XCTAssertEqual(value, 1)
        XCTAssertEqual(factory.dataStorageCalls, 2)
    }

    // MARK: Isolation

    func testAStorageThatWaitsNeverBlocksAnother() async throws {
        // Given
        let storage = UnifiedStorage()
        GatedStorage.gate.reset()
        let waiting = Task {
            try await storage.fetch(forKey: UnifiedStorageKey<GatedStorage, Int>(key: "key"))
        }

        while !GatedStorage.gate.isWaiting {
            await Task.yield()
        }

        // When: another storage, while the first one waits
        try await storage.save(1, forKey: Key<Int>(key: "key"))
        let other = try await storage.fetch(forKey: Key<Int>(key: "key"))

        // Then
        XCTAssertEqual(other, 1)
        XCTAssertTrue(GatedStorage.gate.isWaiting)
        GatedStorage.gate.open()
        let waited = try await waiting.value
        XCTAssertNil(waited)
    }

    // MARK: Errors

    func testStorageAndCoderFailuresKeepTheirCase() async throws {
        // Given
        let storage = UnifiedStorage(factory: RecordingFactory(coder: DataCoderMock(encodeError: error)))
        let key = Key<Int>(key: "key", scope: .init(name: "errors"))

        // When - Then
        await assertThrows(KeyValueCodingError<AsyncDataStorageMock>.coding(error)) { try await storage.save(1, forKey: key) }
        await assertThrows(KeyValueCodingError<GatedStorage>.storage(GatedStorage.failure)) {
            try await storage.clear(storage: GatedStorage.self)
        }
    }

    // MARK: Observation

    func testOnlyTheObservableFactoryPublishes() async throws {
        // Given
        let key = Key<Int>(key: "key", scope: .init(name: "observation"))

        // When
        let unobserved = try await UnifiedStorage().publisher(forKey: key)
        let observed = try await UnifiedStorage(factory: ObservableUnifiedStorageFactory()).publisher(forKey: key)

        // Then
        XCTAssertNil(unobserved)
        XCTAssertNotNil(observed)
    }
}

// MARK: - RecordingFactory

/// Counts its calls, fails the first `failures` creations, and codes with `coder`.
private final class RecordingFactory: UnifiedStorageFactory, @unchecked Sendable {
    static let creationError = MockError(id: 9)

    private let lock = NSLock()
    private let dataCoder: any DataCoder
    private var failures: Int
    private var dataStorages = 0
    private var codingStorages = 0

    var dataStorageCalls: Int {
        lock.withLock { dataStorages }
    }

    var codingStorageCalls: Int {
        lock.withLock { codingStorages }
    }

    init(failures: Int = 0, coder: any DataCoder = DataCoderMock()) {
        self.failures = failures
        self.dataCoder = coder
    }

    func dataStorage<Storage: AsyncKeyValueDataStorage & Sendable>(for scope: Storage.Scope) async throws(Storage.Error) -> Storage {
        let fails = lock.withLock {
            dataStorages += 1
            failures -= 1
            return failures >= 0
        }

        if fails, let error = Self.creationError as? Storage.Error {
            throw error
        }

        return try await Storage(scope: scope)
    }

    func coder<Storage: AsyncKeyValueDataStorage & Sendable>(for storage: Storage) -> any DataCoder {
        dataCoder
    }

    func codingStorage<Storage: AsyncKeyValueDataStorage & Sendable>(for storage: Storage) async -> AsyncKeyValueCodingStorage<Storage> {
        lock.withLock { codingStorages += 1 }
        return AsyncKeyValueCodingStorage(storage: storage, coder: coder(for: storage))
    }
}

// MARK: - GatedStorage

/// Holds every `fetch` until its gate opens, and fails every `clear`.
private actor GatedStorage: AsyncKeyValueDataStorage {
    typealias Key = String
    typealias Error = MockError

    static let gate = Gate()
    static let failure = MockError(id: 2)

    nonisolated let scope: MockScope
    private var values = [String: Data]()

    init(scope: MockScope) {
        self.scope = scope
    }

    func fetch(forKey key: String) async throws(MockError) -> Data? {
        await Self.gate.wait()
        return values[key]
    }

    func save(_ value: Data, forKey key: String) async throws(MockError) {
        values[key] = value
    }

    func delete(forKey key: String) async throws(MockError) {
        values[key] = nil
    }

    func clear() async throws(MockError) {
        throw Self.failure
    }
}

// MARK: - Gate

/// Holds whoever waits until it opens.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    var isWaiting: Bool {
        lock.withLock { waiter != nil }
    }

    func reset() {
        lock.withLock { isOpen = false }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let open = lock.withLock {
                if !isOpen {
                    waiter = continuation
                }

                return isOpen
            }

            if open {
                continuation.resume()
            }
        }
    }

    func open() {
        let waiter = lock.withLock {
            isOpen = true
            defer { self.waiter = nil }
            return self.waiter
        }

        waiter?.resume()
    }
}
