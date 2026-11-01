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
        await assertThrows(CodingStorageError<AsyncDataStorageMock>.storage(RecordingFactory.creationError)) {
            try await storage.save(1, forKey: key)
        }
        try await storage.save(1, forKey: key)
        let value = try await storage.fetch(forKey: key)
        XCTAssertEqual(value, 1)
        XCTAssertEqual(factory.dataStorageCalls, 2)
    }

    func testACancelledCallDoesntCancelTheCreationItShares() async throws {
        // Given: a creation that waits, and two calls waiting for it
        let gate = Gate()
        let factory = GatedCreationFactory(gate: gate)
        let storage = UnifiedStorage(factory: factory)
        let key = Key<Int>(key: "key", scope: .init(name: "cancelled-\(UUID().uuidString)"))
        let cancelled = Task { try await storage.save(1, forKey: key) }
        while !gate.isWaiting {
            await Task.yield()
        }

        let other = Task { try await storage.save(2, forKey: key) }
        try? await Task.sleep(nanoseconds: 100_000_000)

        // When
        cancelled.cancel()
        gate.open()

        // Then: both calls finished with the one storage
        try await cancelled.value
        try await other.value
        XCTAssertEqual(factory.creations, 1)
        let value = try await storage.fetch(forKey: key)
        XCTAssertNotNil(value)
    }

    func testConcurrentCallsShareOneFailedCreationAndALaterCallRetries() async throws {
        // Given
        let factory = RecordingFactory(failures: 1)
        let storage = UnifiedStorage(factory: factory)
        let key = Key<Int>(key: "key", scope: .init(name: "shared-failure"))

        // When: every waiting call gets the one failure, and each removes the failed creation only once
        let failures = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    do {
                        try await storage.save(1, forKey: key)
                        return false
                    } catch {
                        return true
                    }
                }
            }

            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }
        try await storage.save(2, forKey: key)

        // Then: the calls that waited for the failed creation failed, and the retry created the storage once more
        let value = try await storage.fetch(forKey: key)
        XCTAssertGreaterThan(failures, 0)
        XCTAssertEqual(value, 2)
        XCTAssertEqual(factory.dataStorageCalls, 2)
    }

    // MARK: Operations

    func testEachOperationReachesTheKeysStorage() async throws {
        // Given
        let storage = UnifiedStorage(factory: RecordingFactory())
        let key = Key<String>(key: "key", scope: .init(name: "operations"))

        // When - Then
        let initial = try await storage.fetch(forKey: key)
        XCTAssertNil(initial)
        try await storage.save("saved", forKey: key)
        let saved = try await storage.fetch(forKey: key)
        XCTAssertEqual(saved, "saved")
        try await storage.set("set", forKey: key)
        let set = try await storage.fetch(forKey: key)
        XCTAssertEqual(set, "set")
        try await storage.set(nil, forKey: key)
        let unset = try await storage.fetch(forKey: key)
        XCTAssertNil(unset)
        try await storage.save("saved again", forKey: key)
        try await storage.delete(forKey: key)
        let deleted = try await storage.fetch(forKey: key)
        XCTAssertNil(deleted)
    }

    func testClearEmptiesOnlyTheGivenStorageTypeAndScope() async throws {
        // Given: two scopes of a real storage, and another storage type with the same key
        let storage = UnifiedStorage()
        let first = InMemoryKey<String>(key: "key", scope: .own(namespace: "unified-first"))
        let second = InMemoryKey<String>(key: "key", scope: .own(namespace: "unified-second"))
        let other = Key<String>(key: "key", scope: .init(name: "unified-first"))
        try await storage.save("first", forKey: first)
        try await storage.save("first, other key", forKey: InMemoryKey<String>(key: "other", scope: first.scope))
        try await storage.save("second", forKey: second)
        try await storage.save("other type", forKey: other)

        // When
        try await storage.clear(storage: InMemoryStorage.self, forScope: first.scope)

        // Then
        let cleared = try await storage.fetch(forKey: first)
        let clearedOther = try await storage.fetch(forKey: InMemoryKey<String>(key: "other", scope: first.scope))
        let kept = try await storage.fetch(forKey: second)
        let keptType = try await storage.fetch(forKey: other)
        XCTAssertNil(cleared)
        XCTAssertNil(clearedOther)
        XCTAssertEqual(kept, "second")
        XCTAssertEqual(keptType, "other type")
        try await storage.clear(storage: InMemoryStorage.self, forScope: second.scope)
    }

    func testInstancesShareTheStoragesValues() async throws {
        // Given
        let key = InMemoryKey<Int>(key: "key", scope: .own(namespace: "unified-instances"))
        try await UnifiedStorage().save(1, forKey: key)

        // When: a fresh instance clears what another one saved
        let fetched = try await UnifiedStorage().fetch(forKey: key)
        try await UnifiedStorage().clear(storage: InMemoryStorage.self, forScope: key.scope)

        // Then
        let cleared = try await UnifiedStorage().fetch(forKey: key)
        XCTAssertEqual(fetched, 1)
        XCTAssertNil(cleared)
    }

    func testTheDefaultScopeIsClearedWhenNoneIsGiven() async throws {
        // Given
        let storage = UnifiedStorage(factory: RecordingFactory())
        try await storage.save(1, forKey: Key<Int>(key: "key"))
        try await storage.save(2, forKey: Key<Int>(key: "key", scope: .init(name: "kept")))

        // When
        try await storage.clear(storage: AsyncDataStorageMock.self)

        // Then
        let cleared = try await storage.fetch(forKey: Key<Int>(key: "key", scope: .default))
        let kept = try await storage.fetch(forKey: Key<Int>(key: "key", scope: .init(name: "kept")))
        XCTAssertNil(cleared)
        XCTAssertEqual(kept, 2)
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
        await assertThrows(CodingStorageError<AsyncDataStorageMock>.coding(error)) { try await storage.save(1, forKey: key) }
        await assertThrows(CodingStorageError<GatedStorage>.storage(GatedStorage.failure)) {
            try await storage.clear(storage: GatedStorage.self)
        }
    }

    // MARK: Observation

    func testAFactoryCanObserveThroughItsOwnSubclass() async throws {
        // Given: a factory that returns a subclass, which counts the saves it publishes
        let storage = UnifiedStorage(factory: CountingObservableFactory())
        let key = Key<Int>(key: "key", scope: .init(name: "subclass"))
        let values = Values<Int?>()
        let subscription = try await storage.publisher(forKey: key, includingCurrentValue: false)?.sink { values.append($0) }

        // When
        try await storage.save(1, forKey: key)
        try await storage.save(2, forKey: key)

        // Then
        XCTAssertEqual(values.all, [1, 2])
        XCTAssertEqual(Counter.shared.value, 2)
        subscription?.cancel()
    }

    func testOnlyAnObservableStoragePublishes() async throws {
        // Given
        let key = Key<Int>(key: "key", scope: .init(name: "observation"))

        // When
        let unobserved = try await UnifiedStorage().publisher(forKey: key)
        let observed = try await UnifiedStorage(factory: ObservableUnifiedStorageFactory()).publisher(forKey: key)
        let streamed = try await UnifiedStorage(factory: ObservableUnifiedStorageFactory()).stream(forKey: key)

        // Then
        XCTAssertNil(unobserved)
        XCTAssertNotNil(observed)
        XCTAssertNotNil(streamed)
    }

    func testAStreamGetsTheBufferingPolicyItsCallerGives() async throws {
        // Given
        let storage = UnifiedStorage(observable: true)
        let key = Key<Int>(key: "key", scope: .init(name: "buffering-\(UUID().uuidString)"))
        let made = try await storage.stream(forKey: key, includingCurrentValue: false, bufferingPolicy: .bufferingNewest(1))
        let stream = try XCTUnwrap(made)

        // When: changes before the consumer reads any
        try await storage.save(1, forKey: key)
        try await storage.save(2, forKey: key)

        // Then: only the latest was kept
        var iterator = stream.makeAsyncIterator()
        let latest = await iterator.next()
        XCTAssertEqual(latest, 2)
    }

    func testTheObservableFlagChoosesWhetherChangesArePublished() async throws {
        // Given
        let key = InMemoryKey<Int>(key: "key", scope: .own(namespace: "unified-flag"))
        let values = Values<Int?>()

        // When
        let unobserved = try await UnifiedStorage(observable: false).publisher(forKey: key)
        let unstreamed = try await UnifiedStorage().stream(forKey: key)
        let storage = UnifiedStorage(observable: true)
        let subscription = try await storage.publisher(forKey: key)?.sink { values.append($0) }
        try await storage.save(1, forKey: key)
        try await storage.clear(storage: InMemoryStorage.self, forScope: key.scope)

        // Then
        XCTAssertNil(unobserved)
        XCTAssertNil(unstreamed)
        XCTAssertEqual(values.all, [nil, 1, nil])
        subscription?.cancel()
    }

    func testAnObservableStoragePublishesItsWrites() async throws {
        // Given
        let storage = UnifiedStorage(factory: RecordingFactory(observable: true))
        let key = Key<Int>(key: "key", scope: .init(name: "published"))
        let values = Values<Int?>()
        let subscription = try await storage.publisher(forKey: key, includingCurrentValue: false)?.sink { values.append($0) }

        // When
        try await storage.save(1, forKey: key)
        try await storage.set(2, forKey: key)
        try await storage.delete(forKey: key)
        try await storage.save(3, forKey: key)
        try await storage.clear(storage: AsyncDataStorageMock.self, forScope: key.scope)

        // Then
        XCTAssertEqual(values.all, [1, 2, nil, 3, nil])
        subscription?.cancel()
    }
}

// MARK: - RecordingFactory

/// Counts its calls, fails the first `failures` creations, and codes with `coder`.
private final class RecordingFactory: UnifiedStorageFactory, @unchecked Sendable {
    static let creationError = MockError(id: 9)

    private let lock = NSLock()
    private let dataCoder: any DataCoder
    private let observable: Bool
    private var failures: Int
    private var dataStorages = 0
    private var codingStorages = 0

    var dataStorageCalls: Int {
        lock.withLock { dataStorages }
    }

    var codingStorageCalls: Int {
        lock.withLock { codingStorages }
    }

    init(failures: Int = 0, coder: any DataCoder = DataCoderMock(), observable: Bool = false) {
        self.failures = failures
        self.dataCoder = coder
        self.observable = observable
    }

    func dataStorage<Storage: UnifiedStorable>(for scope: Storage.Scope) async throws(Storage.Error) -> Storage {
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

    func coder<Storage: UnifiedStorable>(for storage: Storage) -> any DataCoder {
        dataCoder
    }

    func codingStorage<Storage: UnifiedStorable>(for storage: Storage) async -> AsyncCodingStorage<Storage> {
        lock.withLock { codingStorages += 1 }
        return AsyncCodingStorage(storage: storage, coder: coder(for: storage))
    }

    func observableStorage<Storage: UnifiedStorable>(for storage: AsyncCodingStorage<Storage>) async -> ObservableStorage<Storage>? {
        observable ? ObservableStorage(storage) : nil
    }
}

// MARK: - GatedCreationFactory

/// Creates each storage once its gate opens, counting the creations; a cancelled creation fails, as a server-backed one would.
private final class GatedCreationFactory: UnifiedStorageFactory, @unchecked Sendable {
    static let cancelled = MockError(id: 8)

    private let gate: Gate
    private let lock = NSLock()
    private var count = 0

    var creations: Int {
        lock.withLock { count }
    }

    init(gate: Gate) {
        self.gate = gate
    }

    func dataStorage<Storage: UnifiedStorable>(for scope: Storage.Scope) async throws(Storage.Error) -> Storage {
        await gate.wait()
        if Task.isCancelled, let error = Self.cancelled as? Storage.Error {
            throw error
        }

        lock.withLock { count += 1 }
        return try await Storage(scope: scope)
    }
}

// MARK: - GatedStorage

/// Holds every `fetch` until its gate opens, and fails every `clear`.
private actor GatedStorage: AsyncDataStorage {
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

// MARK: - Values

/// Collects values delivered on any thread.
private final class Values<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values = [Value]()

    var all: [Value] {
        lock.withLock { values }
    }

    func append(_ value: Value) {
        lock.withLock { values.append(value) }
    }
}

// MARK: - CountingObservableFactory

/// Observes through `CountingObservableStorage`.
private struct CountingObservableFactory: UnifiedStorageFactory {
    func coder<Storage: UnifiedStorable>(for storage: Storage) -> any DataCoder {
        DataCoderMock()
    }

    func observableStorage<Storage: UnifiedStorable>(for storage: AsyncCodingStorage<Storage>) async -> ObservableStorage<Storage>? {
        CountingObservableStorage(storage)
    }
}

// MARK: - CountingObservableStorage

/// Counts its saves, then saves and publishes as its superclass does.
private final class CountingObservableStorage<Storage: UnifiedStorable>: ObservableStorage<Storage>, @unchecked Sendable {
    override func save<Value: CodingValue>(_ value: Value, forKey key: CodingStorageKey<Storage, Value>) async throws(Error) {
        Counter.shared.increment()
        try await super.save(value, forKey: key)
    }
}

/// A count shared by every specialization of `CountingObservableStorage`.
private final class Counter: @unchecked Sendable {
    static let shared = Counter()

    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
