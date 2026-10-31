//
//  ObservableKeyValueStorageTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class ObservableKeyValueStorageTests: XCTestCase {
    private typealias Key<Value: CodingValue> = KeyValueCodingStorageKey<InMemoryStorage, Value>

    private let key = Key<Int>(key: "key")

    // MARK: Current Value

    func testThePublisherStartsWithTheCurrentValue() async throws {
        // Given
        let storage = makeStorage()
        let values = Recorded<Int?>()
        try await storage.save(1, forKey: key)

        // When
        let subscription = try await storage.publisher(forKey: key).sink { values.append($0) }
        try await storage.save(2, forKey: key)
        try await storage.delete(forKey: key)

        // Then
        XCTAssertEqual(values.all, [1, 2, nil])
        subscription.cancel()
    }

    func testThePublisherStartsWithNilWhenNothingIsStored() async throws {
        // Given
        let values = Recorded<Int?>()

        // When
        let subscription = try await makeStorage().publisher(forKey: key).sink { values.append($0) }

        // Then
        XCTAssertEqual(values.all, [nil])
        subscription.cancel()
    }

    func testWithoutTheCurrentValueOnlyChangesArePublished() async throws {
        // Given
        let storage = makeStorage()
        let values = Recorded<Int?>()
        try await storage.save(1, forKey: key)

        // When
        let subscription = try await storage.publisher(forKey: key, includingCurrentValue: false).sink { values.append($0) }

        // Then
        XCTAssertEqual(values.all, [])

        // When
        try await storage.save(2, forKey: key)

        // Then
        XCTAssertEqual(values.all, [2])
        subscription.cancel()
    }

    func testTheStreamStartsWithTheCurrentValue() async throws {
        // Given
        let storage = makeStorage()
        try await storage.save(5, forKey: key)

        // When
        let stream = try await storage.stream(forKey: key)
        try await storage.save(6, forKey: key)
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()

        // Then
        XCTAssertEqual(first, 5)
        XCTAssertEqual(second, 6)
    }

    func testAValueSavedBeforeSubscribingWinsOverTheValueRead() async throws {
        // Given
        let storage = makeStorage()
        let values = Recorded<Int?>()
        try await storage.save(1, forKey: key)
        let publisher = try await storage.publisher(forKey: key)

        // When
        try await storage.save(2, forKey: key)
        let subscription = publisher.sink { values.append($0) }

        // Then
        XCTAssertEqual(values.all, [2])
        subscription.cancel()
    }

    func testAValueSavedWhileReadingWinsOverTheValueRead() async throws {
        // Given
        let underlying = SlowReadStorage(scope: .init(name: "slow-\(UUID().uuidString)"))
        await underlying.store(try JSONDataCoder().encode(1), forKey: "key")
        let storage = ObservableKeyValueStorage(AsyncKeyValueCodingStorage(storage: underlying, coder: JSONDataCoder()))
        let key = KeyValueCodingStorageKey<SlowReadStorage, Int>(key: "key")
        let values = Recorded<Int?>()

        // When: a save overtakes the read of the current value
        let publisher = Task { try await storage.publisher(forKey: key) }
        await underlying.waitUntilReading()
        try await storage.save(2, forKey: key)
        await underlying.finishReading()
        let subscription = try await publisher.value.sink { values.append($0) }

        // Then: the value read is older, so it doesn't replace the saved one
        XCTAssertEqual(values.all, [2])
        subscription.cancel()
    }

    func testReadingTheCurrentValueDoesntNotifyChangeSubscribers() async throws {
        // Given
        let storage = makeStorage()
        let changes = Recorded<Int?>()
        let values = Recorded<Int?>()
        try await storage.save(1, forKey: key)
        let changesSubscription = try await storage.publisher(forKey: key, includingCurrentValue: false).sink { changes.append($0) }

        // When
        let valuesSubscription = try await storage.publisher(forKey: key).sink { values.append($0) }

        // Then
        XCTAssertEqual(changes.all, [])
        XCTAssertEqual(values.all, [1])

        // When
        try await storage.save(3, forKey: key)

        // Then
        XCTAssertEqual(changes.all, [3])
        XCTAssertEqual(values.all, [1, 3])
        changesSubscription.cancel()
        valuesSubscription.cancel()
    }

    func testAFailedReadOfTheCurrentValueThrows() async throws {
        // Given
        let namespace = ExactString("unreadable-\(UUID().uuidString)")
        InMemoryStorage(scope: .own(namespace: namespace)).save(Data("not a number".utf8), forKey: "key")
        let storage = makeStorage(namespace)

        // When - Then
        do {
            _ = try await storage.publisher(forKey: key)
            XCTFail("Expected an error")
        } catch {
            guard case .coding = error else {
                return XCTFail("Expected .coding, got \(error)")
            }
        }

        _ = try await storage.publisher(forKey: key, includingCurrentValue: false)
    }

    // MARK: Release

    func testAnUnusedObservationIsReleased() async throws {
        // Given
        let coder = CountingCoder()
        let storage = makeStorage(coder: coder)
        try await storage.save(1, forKey: key)

        // When
        var subscription = try await storage.publisher(forKey: key).sink { _ in }
        _ = try await storage.publisher(forKey: key)

        // Then
        XCTAssertEqual(coder.decodeCalls, 1, "the second publisher shares the observation, so it doesn't read again")

        // When
        subscription.cancel()
        subscription = try await storage.publisher(forKey: key).sink { _ in }

        // Then
        XCTAssertEqual(coder.decodeCalls, 2, "the released observation is made again, so the value is read again")
        subscription.cancel()
    }

    func testAReleasedStreamReleasesItsObservation() async throws {
        // Given
        let coder = CountingCoder()
        let storage = makeStorage(coder: coder)
        try await storage.save(1, forKey: key)

        // When
        do {
            let stream = try await storage.stream(forKey: key)
            _ = stream
        }
        _ = try await storage.publisher(forKey: key)

        // Then
        XCTAssertEqual(coder.decodeCalls, 2)
    }

    // MARK: Delivery

    func testAChangeIsDeliveredBeforeItsSaveReturns() async throws {
        // Given
        let storage = makeStorage()
        let values = Recorded<Int?>()
        let subscription = try await storage.publisher(forKey: key, includingCurrentValue: false).sink { values.append($0) }

        // When
        try await storage.save(1, forKey: key)

        // Then: synchronously, on the thread that saved
        XCTAssertEqual(values.all, [1])
        subscription.cancel()
    }

    func testInstancesOfOneStorageTypeAndScopeSeeEachOthersChanges() async throws {
        // Given
        let namespace = ExactString("shared-\(UUID().uuidString)")
        let observer = makeStorage(namespace)
        let writer = makeStorage(namespace)
        let values = Recorded<Int?>()
        let subscription = try await observer.publisher(forKey: key, includingCurrentValue: false).sink { values.append($0) }

        // When
        try await writer.save(1, forKey: key)
        try await writer.clear()

        // Then
        XCTAssertEqual(values.all, [1, nil])
        subscription.cancel()
    }

    func testOtherScopesStorageTypesAndValueTypesArentNotified() async throws {
        // Given
        let namespace = ExactString("apart-\(UUID().uuidString)")
        let storage = makeStorage(namespace)
        let values = Recorded<Int?>()
        let subscription = try await storage.publisher(forKey: key, includingCurrentValue: false).sink { values.append($0) }

        // When: another scope, another storage type with an equal scope, and another value type
        try await makeStorage(ExactString("\(namespace)-other")).save(1, forKey: key)
        try await ObservableKeyValueStorage(AsyncKeyValueCodingStorage(storage: IsolatedKeyValueDataStorage(InMemoryStorage(scope: .own(namespace: namespace)))))
            .save(2, forKey: KeyValueCodingStorageKey<IsolatedKeyValueDataStorage<InMemoryStorage>, Int>(key: "key"))
        try await storage.save("three", forKey: Key<String>(key: "key"))

        // Then
        XCTAssertEqual(values.all, [])
        subscription.cancel()
    }

    func testClearNotifiesEveryObservedKeyOfTheScope() async throws {
        // Given
        let storage = makeStorage()
        let first = Recorded<Int?>()
        let second = Recorded<String?>()
        try await storage.save(1, forKey: key)
        try await storage.save("two", forKey: Key<String>(key: "other"))
        let firstSubscription = try await storage.publisher(forKey: key, includingCurrentValue: false).sink { first.append($0) }
        let secondSubscription = try await storage.publisher(forKey: Key<String>(key: "other"), includingCurrentValue: false).sink { second.append($0) }

        // When
        try await storage.clear()

        // Then
        XCTAssertEqual(first.all, [nil])
        XCTAssertEqual(second.all, [nil])
        firstSubscription.cancel()
        secondSubscription.cancel()
    }

    func testASubscriberThatSavesDoesntDeadlock() async throws {
        // Given: a subscriber that saves the same key once more from its callback
        let storage = makeStorage()
        let key = key
        let values = Recorded<Int?>()
        let saved = expectation(description: "saved again")
        let subscription = try await storage.publisher(forKey: key, includingCurrentValue: false).sink { value in
            values.append(value)
            if value == 1 {
                Task {
                    try await storage.save(2, forKey: key)
                    saved.fulfill()
                }
            }
        }

        // When
        try await storage.save(1, forKey: key)

        // Then
        await fulfillment(of: [saved], timeout: 5)
        XCTAssertEqual(values.all, [1, 2])
        subscription.cancel()
    }

    // MARK: Forwarding

    func testOperationsAndErrorsPassThrough() async throws {
        // Given
        let underlying = AsyncDataStorageMock(scope: .init(name: "forwarding"))
        let storage = ObservableKeyValueStorage(AsyncKeyValueCodingStorage(storage: underlying, coder: DataCoderMock()))
        let key = KeyValueCodingStorageKey<AsyncDataStorageMock, Int>(key: "key")

        // When
        try await storage.save(1, forKey: key)
        let fetched = try await storage.fetch(forKey: key)
        try await storage.set(nil, forKey: key)
        try await storage.clear()

        // Then
        XCTAssertEqual(fetched, 1)
        XCTAssertEqual(storage.scope, underlying.scope)
        let calls = await underlying.calls
        XCTAssertEqual(calls, [.save(Data("1".utf8), "key"), .fetch("key"), .delete("key"), .clear])

        // When - Then
        let error = MockError(id: 1)
        await underlying.fail(with: error)
        await assertThrows(KeyValueCodingError<AsyncDataStorageMock>.storage(error)) { try await storage.save(1, forKey: key) }
    }

    // MARK: Helpers

    private func makeStorage(_ namespace: ExactString = .init("observable-\(UUID().uuidString)"),
                             coder: any DataCoder = JSONDataCoder()) -> ObservableKeyValueStorage<InMemoryStorage> {
        ObservableKeyValueStorage(AsyncKeyValueCodingStorage(storage: InMemoryStorage(scope: .own(namespace: namespace)), coder: coder))
    }
}

// MARK: - SlowReadStorage

/// Takes the stored value, then waits until the test lets the read return, like a slow read that a save overtakes.
private actor SlowReadStorage: AsyncKeyValueDataStorage {
    typealias Key = String
    typealias Error = Never

    nonisolated let scope: MockScope
    private var values = [String: Data]()
    private var pausedRead: CheckedContinuation<Void, Never>?
    private var readStarted: CheckedContinuation<Void, Never>?

    init(scope: MockScope) {
        self.scope = scope
    }

    func fetch(forKey key: String) async -> Data? {
        let value = values[key]
        readStarted?.resume()
        readStarted = nil
        await withCheckedContinuation { pausedRead = $0 }
        return value
    }

    func save(_ value: Data, forKey key: String) {
        values[key] = value
    }

    func delete(forKey key: String) {
        values[key] = nil
    }

    func clear() {
        values = [:]
    }

    func store(_ value: Data, forKey key: String) {
        values[key] = value
    }

    /// Returns once a read has taken the stored value and is waiting.
    func waitUntilReading() async {
        guard pausedRead == nil else {
            return
        }

        await withCheckedContinuation { readStarted = $0 }
    }

    func finishReading() {
        pausedRead?.resume()
        pausedRead = nil
    }
}

// MARK: - CountingCoder

/// JSON, counting its decodes.
private final class CountingCoder: DataCoder, @unchecked Sendable {
    private let lock = NSLock()
    private var decodes = 0

    var decodeCalls: Int {
        lock.withLock { decodes }
    }

    func encode<Value: CodingValue>(_ value: Value) throws -> Data {
        try JSONDataCoder().encode(value)
    }

    func decode<Value: CodingValue>(_ data: Data) throws -> Value {
        lock.withLock { decodes += 1 }
        return try JSONDataCoder().decode(data)
    }
}

// MARK: - Recorded

/// Collects values delivered on any thread.
private final class Recorded<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values = [Value]()

    var all: [Value] {
        lock.withLock { values }
    }

    func append(_ value: Value) {
        lock.withLock { values.append(value) }
    }
}
