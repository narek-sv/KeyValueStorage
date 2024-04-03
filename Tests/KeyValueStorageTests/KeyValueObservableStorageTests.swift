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
        await storage.publisher(forKey: key).sink(receiveValue: {
            // Then
            XCTAssertEqual(operations[operationIndex1].1, $0)
            operationIndex1 += 1
            publisherExpectation.fulfill()
        }).store(in: &subscriptions)
        await storage.publisher(forKey: key).sink(receiveValue: {
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
        await storage1.publisher(forKey: key).sink(receiveValue: {
            // Then
            XCTAssertEqual(operations[operationIndex1].1, $0)
            operationIndex1 += 1
            publisherExpectation.fulfill()
        }).store(in: &subscriptions)
        await storage2.publisher(forKey: key).sink(receiveValue: {
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
        await storage1.publisher(forKey: key).sink(receiveValue: {
            // Then
            XCTAssertEqual(operations[operationIndex1].1, $0)
            operationIndex1 += 1
            publisherExpectation.fulfill()
        }).store(in: &subscriptions)
        await storage2.publisher(forKey: key).sink(receiveValue: {
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
        await storage1.publisher(forKey: key).sink(receiveValue: {
            // Then
            XCTAssertEqual(operations1[operationIndex1].1, $0)
            operationIndex1 += 1
            publisherExpectation.fulfill()
        }).store(in: &subscriptions)
        await storage2.publisher(forKey: key).sink(receiveValue: {
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
        
        let task = Task.detached {
            var operationIndex = 0

            for await change in await storage.stream(forKey: key) {
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

extension XCTestCase {
    func wait(to expectations: [XCTestExpectation], timeout: TimeInterval) async {
#if swift(>=5.8)
        await fulfillment(of: expectations, timeout: timeout)
#else
        wait(for: expectations, timeout: timeout)
#endif
    }
}


