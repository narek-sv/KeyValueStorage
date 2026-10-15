//
//  KeyValueObservableStorageTests.swift
//
//
//  Created by Narek Sahakyan on 01.03.24.
//

import XCTest
import Foundation
import Combine
@testable import KeyValueStorage

final class KeyValueObservableStorageTests: XCTestCase {
    var underlyingStorage: InMemoryStorage!
    var coder: DataCoder!
    
    @InMemoryActor
    override func setUp() async throws {
        underlyingStorage = InMemoryStorage()
        coder = JSONDataCoder()
        InMemoryStorage.container = [nil: [:]]
    }
    
    func testPublisherSameStorageSameDomainSameKey() async throws  {
        // Given
        let operations = [
            ("save", 1),
            ("save", 2),
            ("delete", nil),
            ("delete", nil),
            ("set", 4),
            ("set", nil),
            ("save", 10),
            ("clear", nil)
        ]
        let publisherExpectation = expectation(description: "testPublisherSave")
        publisherExpectation.expectedFulfillmentCount = operations.count * 2
        
        var operationIndex1 = 0
        var operationIndex2 = 0
        let storage = await KeyValueObservableStorage(storage: InMemoryStorage(), coder: coder)
        let key = KeyValueCodingStorageKey<InMemoryStorage, Int>(key: "key")
        var subscriptions = Set<AnyCancellable>()
        try await storage.publisher(forKey: key, includingCurrentValue: false).sink(receiveValue: {
            // Then
            XCTAssertEqual(operations[operationIndex1].1, $0)
            operationIndex1 += 1
            publisherExpectation.fulfill()
        }).store(in: &subscriptions)
        try await storage.publisher(forKey: key, includingCurrentValue: false).sink(receiveValue: {
            // Then
            XCTAssertEqual(operations[operationIndex2].1, $0)
            operationIndex2 += 1
            publisherExpectation.fulfill()
        }).store(in: &subscriptions)
        
        // When
        for operation in operations {
            switch operation {
            case let ("save", value):
                try await storage.save(value!, forKey: key)
            case let ("set", value):
                try await storage.set(value, forKey: key)
            case ("delete", _):
                try await storage.delete(forKey: key)
            case ("clear", _):
                try await storage.clear()
            default:
                break
            }
        }
        
        await wait(to: [publisherExpectation], timeout: 1)
    }
    
    func testPublisherDifferentStorageSameDomainSameKey1() async throws  {
        // Given
        let operations = [
            ("save", 1, 1),
            ("save", 2, 2),
            ("delete", nil, 2),
            ("delete", nil, 1),
            ("set", 4, 2),
            ("set", nil, 1),
            ("save", 10, 1),
            ("clear", nil, 1)
        ]
        let publisherExpectation = expectation(description: "testPublisherSave")
        publisherExpectation.expectedFulfillmentCount = operations.count * 2
        
        var operationIndex1 = 0
        var operationIndex2 = 0
        let storage1 = await KeyValueObservableStorage(storage: InMemoryStorage(), coder: coder)
        let storage2 = await KeyValueObservableStorage(storage: InMemoryStorage(), coder: coder)
        let key = KeyValueCodingStorageKey<InMemoryStorage, Int>(key: "key")
        var subscriptions = Set<AnyCancellable>()
        try await storage1.publisher(forKey: key, includingCurrentValue: false).sink(receiveValue: {
            // Then
            XCTAssertEqual(operations[operationIndex1].1, $0)
            operationIndex1 += 1
            publisherExpectation.fulfill()
        }).store(in: &subscriptions)
        try await storage2.publisher(forKey: key, includingCurrentValue: false).sink(receiveValue: {
            // Then
            XCTAssertEqual(operations[operationIndex2].1, $0)
            operationIndex2 += 1
            publisherExpectation.fulfill()
        }).store(in: &subscriptions)
        
        // When
        for operation in operations {
            let storage = operation.2 == 1 ? storage1 : storage2
            switch operation {
            case let ("save", value, _):
                try await storage.save(value!, forKey: key)
            case let ("set", value, _):
                try await storage.set(value, forKey: key)
            case ("delete", _ , _):
                try await storage.delete(forKey: key)
            case ("clear", _ , _):
                try await storage.clear()
            default:
                break
            }
        }
        
        await wait(to: [publisherExpectation], timeout: 1)
    }
    
    func testPublisherDifferentStorageSameDomainSameKey2() async throws  {
        // Given
        let operations = [
            ("save", 1, 1),
            ("save", 2, 2),
            ("delete", nil, 2),
            ("delete", nil, 1),
            ("set", 4, 2),
            ("set", nil, 1),
            ("save", 10, 1),
            ("clear", nil, 1)
        ]
        let publisherExpectation = expectation(description: "testPublisherSave")
        publisherExpectation.expectedFulfillmentCount = operations.count * 2
        
        var operationIndex1 = 0
        var operationIndex2 = 0
        let storage1 = await KeyValueObservableStorage(storage: InMemoryStorage(domain: "x"), coder: coder)
        let storage2 = await KeyValueObservableStorage(storage: InMemoryStorage(domain: "x"), coder: coder)
        let key = KeyValueCodingStorageKey<InMemoryStorage, Int>(key: "key")
        var subscriptions = Set<AnyCancellable>()
        try await storage1.publisher(forKey: key, includingCurrentValue: false).sink(receiveValue: {
            // Then
            XCTAssertEqual(operations[operationIndex1].1, $0)
            operationIndex1 += 1
            publisherExpectation.fulfill()
        }).store(in: &subscriptions)
        try await storage2.publisher(forKey: key, includingCurrentValue: false).sink(receiveValue: {
            // Then
            XCTAssertEqual(operations[operationIndex2].1, $0)
            operationIndex2 += 1
            publisherExpectation.fulfill()
        }).store(in: &subscriptions)
        
        // When
        for operation in operations {
            let storage = operation.2 == 1 ? storage1 : storage2
            switch operation {
            case let ("save", value, _):
                try await storage.save(value!, forKey: key)
            case let ("set", value, _):
                try await storage.set(value, forKey: key)
            case ("delete", _ , _):
                try await storage.delete(forKey: key)
            case ("clear", _ , _):
                try await storage.clear()
            default:
                break
            }
        }
        
        await wait(to: [publisherExpectation], timeout: 1)
    }
    
    func testDifferentDomainsSameKey() async throws {
        // Given
        let operations1 = [
            ("save", 1),
            ("save", 2),
            ("delete", nil),
            ("delete", nil),
            ("set", 4),
            ("set", nil),
            ("save", 10),
            ("clear", nil)
        ]
        let operations2 = [
            ("delete", nil),
            ("save", 6),
            ("delete", nil),
            ("set", 4),
            ("save", 50),
            ("clear", nil),
            ("save", 32)
        ]
        let publisherExpectation = expectation(description: "testPublisherSave")
        publisherExpectation.expectedFulfillmentCount = operations1.count + operations2.count
        
        var operationIndex1 = 0
        var operationIndex2 = 0
        let storage1 = await KeyValueObservableStorage(storage: InMemoryStorage(), coder: coder)
        let storage2 = await KeyValueObservableStorage(storage: InMemoryStorage(domain: "other"), coder: coder)
        let key = KeyValueCodingStorageKey<InMemoryStorage, Int>(key: "key")
        var subscriptions = Set<AnyCancellable>()
        try await storage1.publisher(forKey: key, includingCurrentValue: false).sink(receiveValue: {
            // Then
            XCTAssertEqual(operations1[operationIndex1].1, $0)
            operationIndex1 += 1
            publisherExpectation.fulfill()
        }).store(in: &subscriptions)
        try await storage2.publisher(forKey: key, includingCurrentValue: false).sink(receiveValue: {
            // Then
            XCTAssertEqual(operations2[operationIndex2].1, $0)
            operationIndex2 += 1
            publisherExpectation.fulfill()
        }).store(in: &subscriptions)
        
        // When
        for operation in operations1 {
            switch operation {
            case let ("save", value):
                try await storage1.save(value!, forKey: key)
            case let ("set", value):
                try await storage1.set(value, forKey: key)
            case ("delete", _):
                try await storage1.delete(forKey: key)
            case ("clear", _):
                try await storage1.clear()
            default:
                break
            }
        }
        
        for operation in operations2 {
            switch operation {
            case let ("save", value):
                try await storage2.save(value!, forKey: key)
            case let ("set", value):
                try await storage2.set(value, forKey: key)
            case ("delete", _):
                try await storage2.delete(forKey: key)
            case ("clear", _):
                try await storage2.clear()
            default:
                break
            }
        }
        
        await wait(to: [publisherExpectation], timeout: 1)
    }
    
    func testAsyncStream() async throws {
        // Given
        let operations = [
            ("save", 1),
            ("save", 2),
            ("delete", nil),
            ("delete", nil),
            ("set", 4),
            ("set", nil),
            ("save", 10),
            ("clear", nil)
        ]
        let publisherExpectation = expectation(description: "testPublisherSave")
        publisherExpectation.expectedFulfillmentCount = operations.count
        
        let storage = await KeyValueObservableStorage(storage: InMemoryStorage(), coder: coder)
        let key = KeyValueCodingStorageKey<InMemoryStorage, Int>(key: "key")
        
        let stream = try await storage.stream(forKey: key, includingCurrentValue: false)
        let task = Task.detached {
            var operationIndex = 0

            for await change in stream {
                XCTAssertEqual(operations[operationIndex].1, change)
                operationIndex += 1
                publisherExpectation.fulfill()
            }
        }
        
        // When
        for operation in operations {
            switch operation {
            case let ("save", value):
                print("save")
                try await storage.save(value!, forKey: key)
            case let ("set", value):
                print("set")
                try await storage.set(value, forKey: key)
            case ("delete", _):
                print("delete")
                try await storage.delete(forKey: key)
            case ("clear", _):
                print("clear")
                try await storage.clear()
            default:
                break
            }
        }
        
        await wait(to: [publisherExpectation], timeout: 1)
        task.cancel()
    }
}

extension KeyValueObservableStorageTests {
    func testPublisherStartsWithCurrentValue() async throws {
        // Given
        let storage = KeyValueObservableStorage(storage: await InMemoryStorage(domain: "currentValue"), coder: coder)
        let key = KeyValueCodingStorageKey<InMemoryStorage, Int>(key: "key")
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
    
    func testPublisherStartsWithNilWhenNothingIsStored() async throws {
        // Given
        let storage = KeyValueObservableStorage(storage: await InMemoryStorage(domain: "noValue"), coder: coder)
        let values = Recorded<Int?>()
        
        // When
        let subscription = try await storage.publisher(forKey: KeyValueCodingStorageKey<InMemoryStorage, Int>(key: "key")).sink { values.append($0) }
        
        // Then
        XCTAssertEqual(values.all, [nil])
        subscription.cancel()
    }
    
    func testPublisherWithoutCurrentValueEmitsOnlyChanges() async throws {
        // Given
        let storage = KeyValueObservableStorage(storage: await InMemoryStorage(domain: "changesOnly"), coder: coder)
        let key = KeyValueCodingStorageKey<InMemoryStorage, Int>(key: "key")
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
    
    func testStreamStartsWithCurrentValue() async throws {
        // Given
        let storage = KeyValueObservableStorage(storage: await InMemoryStorage(domain: "streamCurrentValue"), coder: coder)
        let key = KeyValueCodingStorageKey<InMemoryStorage, Int>(key: "key")
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
    
    func testValueSavedBeforeSubscribingWinsOverReadValue() async throws {
        // Given
        let storage = KeyValueObservableStorage(storage: await InMemoryStorage(domain: "savedBeforeSubscribing"), coder: coder)
        let key = KeyValueCodingStorageKey<InMemoryStorage, Int>(key: "key")
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
    
    func testValueSavedWhileReadingCurrentValueWinsOverReadValue() async throws {
        // Given
        let underlyingStorage = SlowReadStorage()
        await underlyingStorage.save(try await coder.encode(1), forKey: "key")
        let storage = KeyValueObservableStorage(storage: underlyingStorage, coder: coder)
        let key = KeyValueCodingStorageKey<SlowReadStorage, Int>(key: "key")
        let values = Recorded<Int?>()
        
        // When: a save overtakes the read of the current value
        let publisher = Task { try await storage.publisher(forKey: key) }
        await underlyingStorage.waitUntilReading()
        try await storage.save(2, forKey: key)
        await underlyingStorage.finishReading()
        let subscription = try await publisher.value.sink { values.append($0) }
        
        // Then: the value that was read is older, so it doesn't replace the saved one
        XCTAssertEqual(values.all, [2])
        subscription.cancel()
    }
    
    func testReadingCurrentValueDoesntNotifyChangeSubscribers() async throws {
        // Given
        let storage = KeyValueObservableStorage(storage: await InMemoryStorage(domain: "seeding"), coder: coder)
        let key = KeyValueCodingStorageKey<InMemoryStorage, Int>(key: "key")
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
    
    func testFailureToReadCurrentValueThrows() async throws {
        // Given
        let underlyingStorage = await InMemoryStorage(domain: "unreadable")
        await underlyingStorage.save(Data("not a number".utf8), forKey: "key")
        let storage = KeyValueObservableStorage(storage: underlyingStorage, coder: coder)
        let key = KeyValueCodingStorageKey<InMemoryStorage, Int>(key: "key")
        
        do {
            // When
            _ = try await storage.publisher(forKey: key)
            XCTFail("Expected error")
        } catch {
            // Then
            XCTAssertTrue(error is DecodingError)
        }
        
        // When - Then
        _ = try await storage.publisher(forKey: key, includingCurrentValue: false)
        await underlyingStorage.clear()
    }
    
    func testObservationIsReleasedWhenUnused() async throws {
        // Given
        let coder = CountingCoder()
        let storage = KeyValueObservableStorage(storage: await InMemoryStorage(domain: "release"), coder: coder)
        let key = KeyValueCodingStorageKey<InMemoryStorage, Int>(key: "key")
        try await storage.save(1, forKey: key)
        
        // When
        var subscription = try await storage.publisher(forKey: key).sink { _ in }
        _ = try await storage.publisher(forKey: key)
        
        // Then
        XCTAssertEqual(coder.decodeCalls, 1, "the second publisher shares the observation, so it doesn't read again")
        
        // When
        subscription.cancel()
        await flushReleases()
        subscription = try await storage.publisher(forKey: key).sink { _ in }
        
        // Then
        XCTAssertEqual(coder.decodeCalls, 2, "the released observation is created again, so the value is read again")
        subscription.cancel()
    }
    
    func testStreamReleasesObservationWhenDeallocated() async throws {
        // Given
        let coder = CountingCoder()
        let storage = KeyValueObservableStorage(storage: await InMemoryStorage(domain: "streamRelease"), coder: coder)
        let key = KeyValueCodingStorageKey<InMemoryStorage, Int>(key: "key")
        try await storage.save(1, forKey: key)
        
        // When
        do {
            let stream = try await storage.stream(forKey: key)
            _ = stream
        }
        await flushReleases()
        _ = try await storage.publisher(forKey: key)
        
        // Then
        XCTAssertEqual(coder.decodeCalls, 2)
    }
    
    // MARK: Helpers
    
    /// Releasing hops to the observation actor, so wait until the pending releases ran.
    private func flushReleases() async {
        for _ in 0..<3 {
            await Task { @CodingStorageActor in }.value
        }
    }
}

/// Takes the stored value, then waits until the test lets the read return, like a slow read that a save overtakes.
private actor SlowReadStorage: KeyValueDataStorage {
    typealias Key = String
    typealias Domain = String
    enum Error: Swift.Error { }
    
    nonisolated let domain: Domain?
    private var values = [Key: Data]()
    private var pausedRead: CheckedContinuation<Void, Never>?
    private var readStarted: CheckedContinuation<Void, Never>?
    
    init() {
        self.domain = nil
    }
    
    init(domain: Domain) {
        self.domain = domain
    }
    
    func fetch(forKey key: Key) async -> Data? {
        let value = values[key]
        readStarted?.resume()
        readStarted = nil
        await withCheckedContinuation { pausedRead = $0 }
        return value
    }
    
    func save(_ value: Data, forKey key: Key) {
        values[key] = value
    }
    
    func set(_ value: Data?, forKey key: Key) {
        values[key] = value
    }
    
    func delete(forKey key: Key) {
        values[key] = nil
    }
    
    func clear() {
        values.removeAll()
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

/// Collects values delivered on any thread.
private final class Recorded<Value>: @unchecked Sendable {
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

extension XCTestCase {
    func wait(to expectations: [XCTestExpectation], timeout: TimeInterval) async {
#if swift(>=5.8)
        await fulfillment(of: expectations, timeout: timeout)
#else
        wait(for: expectations, timeout: timeout)
#endif
    }
}


