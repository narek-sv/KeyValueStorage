//
//  InMemoryStorageTests.swift
//  
//
//  Created by Narek Sahakyan on 31.12.23.
//

import XCTest
import Foundation
@testable import UnifiedStorage

@InMemoryActor
final class InMemoryStorageTests: XCTestCase {
    static let Storage = InMemoryStorage.self
    
    func testInMemoryDomain() throws {
        // Given
        let storage1 = InMemoryStorage()
        let storage2 = InMemoryStorage(domain: "other")
        
        // When - Then
        XCTAssertEqual(storage1.domain, nil)
        XCTAssertEqual(storage2.domain, "other")
    }
    
    func testInMemoryFetch() throws {
        // Given
        let storage = InMemoryStorage()
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        InMemoryStorage.container = [:]
        
        // When
        var fetched1 = storage.fetch(forKey: key1)
        var fetched2 = storage.fetch(forKey: key2)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)

        // When
        InMemoryStorage.container = [nil: [key1: data1]]
        fetched1 = storage.fetch(forKey: key1)
        fetched2 = storage.fetch(forKey: key2)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertNil(fetched2)

        // When
        InMemoryStorage.container = [nil: [key1: data2]]
        fetched1 = storage.fetch(forKey: key1)
        fetched2 = storage.fetch(forKey: key2)

        // Then
        XCTAssertEqual(fetched1, data2)
        XCTAssertNil(fetched2)
        
        // When
        InMemoryStorage.container = [nil: [key1: data1, key2: data2]]
        fetched1 = storage.fetch(forKey: key1)
        fetched2 = storage.fetch(forKey: key2)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertEqual(fetched2, data2)
        
        // When
        InMemoryStorage.container = [nil: [key2: data1]]
        fetched1 = storage.fetch(forKey: key1)
        fetched2 = storage.fetch(forKey: key2)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertEqual(fetched2, data1)
        
        // When
        InMemoryStorage.container = [nil: [:]]
        fetched1 = storage.fetch(forKey: key1)
        fetched2 = storage.fetch(forKey: key2)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
    }
    
    func testInMemoryFetchDifferentDomains() throws {
        // Given
        let storage1 = InMemoryStorage()
        let storage2 = InMemoryStorage(domain: "other")
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        InMemoryStorage.container = [:]
        
        // When
        var fetched1 = storage1.fetch(forKey: key)
        var fetched2 = storage2.fetch(forKey: key)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)

        // When
        InMemoryStorage.container = [nil: [key: data1]]
        fetched1 = storage1.fetch(forKey: key)
        fetched2 = storage2.fetch(forKey: key)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertNil(fetched2)

        // When
        InMemoryStorage.container = ["other": [key: data2]]
        fetched1 = storage1.fetch(forKey: key)
        fetched2 = storage2.fetch(forKey: key)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertEqual(fetched2, data2)

        // When
        InMemoryStorage.container = [nil: [key: data2]]
        fetched1 = storage1.fetch(forKey: key)
        fetched2 = storage2.fetch(forKey: key)

        // Then
        XCTAssertEqual(fetched1, data2)
        XCTAssertNil(fetched2)

        // When
        InMemoryStorage.container = [nil: [key: data1], "other": [key: data2]]
        fetched1 = storage1.fetch(forKey: key)
        fetched2 = storage2.fetch(forKey: key)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertEqual(fetched2, data2)
        
        // When
        InMemoryStorage.container = [nil: [:], "other": [:]]
        fetched1 = storage1.fetch(forKey: key)
        fetched2 = storage2.fetch(forKey: key)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
    }
    
    func testInMemorySave() throws {
        // Given
        let storage = InMemoryStorage()
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        InMemoryStorage.container = [:]
        
        // When
        storage.save(data1, forKey: key1)

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key1], data1)
        XCTAssertNil(InMemoryStorage.container[nil]?[key2])

        // When
        storage.save(data2, forKey: key1)

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key1], data2)
        XCTAssertNil(InMemoryStorage.container[nil]?[key2])

        // When
        storage.save(data1, forKey: key2)
        
        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key1], data2)
        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data1)
    }
    
    func testInMemorySaveDifferentDomains() throws {
        // Given
        let storage1 = InMemoryStorage()
        let storage2 = InMemoryStorage(domain: "other")
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        InMemoryStorage.container = [:]
        
        // When
        storage1.save(data1, forKey: key)

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key], data1)
        XCTAssertNil(InMemoryStorage.container["other"]?[key])

        // When
        storage2.save(data2, forKey: key)

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key], data1)
        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)

        // When
        storage1.save(data2, forKey: key)
        
        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key], data2)
        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)
    }
    
    func testInMemoryDelete() throws {
        // Given
        let storage = InMemoryStorage()
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        InMemoryStorage.container = [nil: [key1: data1, key2: data2]]
        
        // When
        storage.delete(forKey: key1)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data2)

        // When
        storage.delete(forKey: key1)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data2)

        // When
        storage.delete(forKey: key2)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
        XCTAssertNil(InMemoryStorage.container[nil]?[key2])
    }
    
    func testInMemoryDeleteDifferentDomains() throws {
        // Given
        let storage1 = InMemoryStorage()
        let storage2 = InMemoryStorage(domain: "other")
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        InMemoryStorage.container = [nil: [key: data1], "other": [key: data2]]
        
        // When
        storage1.delete(forKey: key)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key])
        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)

        // When
        storage1.delete(forKey: key)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key])
        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)

        // When
        storage2.delete(forKey: key)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key])
        XCTAssertNil(InMemoryStorage.container["other"]?[key])
    }
    
    func testInMemorySet() throws {
        // Given
        let storage = InMemoryStorage()
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        InMemoryStorage.container = [nil: [key1: data1, key2: data2]]
        
        // When
        storage.set(data2, forKey: key1)

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key1], data2)
        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data2)

        // When
        storage.set(nil, forKey: key1)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data2)
        
        // When
        storage.set(data1, forKey: key2)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data1)
        
        // When
        storage.set(nil, forKey: key2)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
        XCTAssertNil(InMemoryStorage.container[nil]?[key2])
    }
    
    func testInMemorySetDifferentDomains() throws {
        // Given
        let storage1 = InMemoryStorage()
        let storage2 = InMemoryStorage(domain: "other")
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        InMemoryStorage.container = [nil: [key: data1], "other": [key: data2]]
        
        // When
        storage1.set(data2, forKey: key)

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key], data2)
        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)

        // When
        storage1.set(nil, forKey: key)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key])
        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)
        
        // When
        storage2.set(data1, forKey: key)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key])
        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data1)

        // When
        storage2.set(nil, forKey: key)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key])
        XCTAssertNil(InMemoryStorage.container["other"]?[key])
    }
    
    func testInMemoryClear() throws {
        // Given
        let storage1 = InMemoryStorage()
        let storage2 = InMemoryStorage(domain: "other")
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        InMemoryStorage.container = [nil: [key1: data1, key2: data2], "other": [key1: data2, key2: data1]]
        
        // When
        storage1.clear()

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil], [:])
        XCTAssertEqual(InMemoryStorage.container["other"]?[key1], data2)
        XCTAssertEqual(InMemoryStorage.container["other"]?[key2], data1)

        // When
        storage1.clear()

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil], [:])
        XCTAssertEqual(InMemoryStorage.container["other"]?[key1], data2)
        XCTAssertEqual(InMemoryStorage.container["other"]?[key2], data1)
        
        // When
        InMemoryStorage.container = [nil: [key1: data1, key2: data2], "other": [key1: data2, key2: data1]]
        storage2.clear()

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key1], data1)
        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data2)
        XCTAssertEqual(InMemoryStorage.container["other"], [:])


        // When
        storage1.clear()

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil], [:])
        XCTAssertEqual(InMemoryStorage.container["other"], [:])
    }
    
    func testThreadSafety() throws {
        // Given
        let iterations = 10000
        let storage = InMemoryStorage()
        let promise = expectation(description: "testThreadSafety")
        let group = DispatchGroup()
        for _ in 1...iterations { group.enter() }
        
        // When
        DispatchQueue.concurrentPerform(iterations: iterations) { number in
            let operation = Int.random(in: 0...4)
            let key = "\(Int.random(in: 1000...9999))"
            
            Task.detached {
                switch operation {
                case 0:
                    _ = await storage.fetch(forKey: key)
                case 1:
                    await storage.save(.init(), forKey: key)
                case 2:
                    await storage.delete(forKey: key)
                case 3:
                    await storage.set(Bool.random() ? nil : .init(), forKey: key)
                case 4:
                    await storage.clear()
                default:
                    break
                }
                            
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            promise.fulfill()
        }
        
        wait(for: [promise], timeout: 5)
    }
}

