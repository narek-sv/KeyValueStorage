//
//  InMemoryStorageTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.12.23.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class InMemoryStorageTests: XCTestCase {
    static let otherStorageScope = "other"
    var standardStorage: InMemoryStorage!
    var otherStorage: InMemoryStorage!
    
    @InMemoryActor
    override func setUp() async throws {
        standardStorage = InMemoryStorage()
        otherStorage = InMemoryStorage(scope: Self.otherStorageScope)
        
        InMemoryStorage.container = [:]
    }
    
    @InMemoryActor
    func testInMemoryScope() async {
        XCTAssertEqual(standardStorage.scope, nil)
        XCTAssertEqual(otherStorage.scope, Self.otherStorageScope)
    }
    
    @InMemoryActor
    func testInMemoryFetch() async {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        
        // When
        var fetched1 = standardStorage.fetch(forKey: key1)
        var fetched2 = standardStorage.fetch(forKey: key2)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)

        // When
        InMemoryStorage.container = [nil: [key1: data1]]
        fetched1 = standardStorage.fetch(forKey: key1)
        fetched2 = standardStorage.fetch(forKey: key2)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertNil(fetched2)

        // When
        InMemoryStorage.container = [nil: [key1: data2]]
        fetched1 = standardStorage.fetch(forKey: key1)
        fetched2 = standardStorage.fetch(forKey: key2)

        // Then
        XCTAssertEqual(fetched1, data2)
        XCTAssertNil(fetched2)
        
        // When
        InMemoryStorage.container = [nil: [key1: data1, key2: data2]]
        fetched1 = standardStorage.fetch(forKey: key1)
        fetched2 = standardStorage.fetch(forKey: key2)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertEqual(fetched2, data2)
        
        // When
        InMemoryStorage.container = [nil: [key2: data1]]
        fetched1 = standardStorage.fetch(forKey: key1)
        fetched2 = standardStorage.fetch(forKey: key2)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertEqual(fetched2, data1)
        
        // When
        InMemoryStorage.container = [nil: [:]]
        fetched1 = standardStorage.fetch(forKey: key1)
        fetched2 = standardStorage.fetch(forKey: key2)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
    }
    
    @InMemoryActor
    func testInMemoryFetchDifferentScopes() async {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        
        // When
        var fetched1 = standardStorage.fetch(forKey: key)
        var fetched2 = otherStorage.fetch(forKey: key)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)

        // When
        InMemoryStorage.container = [nil: [key: data1]]
        fetched1 = standardStorage.fetch(forKey: key)
        fetched2 = otherStorage.fetch(forKey: key)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertNil(fetched2)

        // When
        InMemoryStorage.container = ["other": [key: data2]]
        fetched1 = standardStorage.fetch(forKey: key)
        fetched2 = otherStorage.fetch(forKey: key)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertEqual(fetched2, data2)

        // When
        InMemoryStorage.container = [nil: [key: data2]]
        fetched1 = standardStorage.fetch(forKey: key)
        fetched2 = otherStorage.fetch(forKey: key)

        // Then
        XCTAssertEqual(fetched1, data2)
        XCTAssertNil(fetched2)

        // When
        InMemoryStorage.container = [nil: [key: data1], "other": [key: data2]]
        fetched1 = standardStorage.fetch(forKey: key)
        fetched2 = otherStorage.fetch(forKey: key)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertEqual(fetched2, data2)
        
        // When
        InMemoryStorage.container = [nil: [:], "other": [:]]
        fetched1 = standardStorage.fetch(forKey: key)
        fetched2 = otherStorage.fetch(forKey: key)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
    }
    
    @InMemoryActor
    func testInMemorySave() async {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        
        // When
        standardStorage.save(data1, forKey: key1)

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key1], data1)
        XCTAssertNil(InMemoryStorage.container[nil]?[key2])

        // When
        standardStorage.save(data2, forKey: key1)

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key1], data2)
        XCTAssertNil(InMemoryStorage.container[nil]?[key2])

        // When
        standardStorage.save(data1, forKey: key2)
        
        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key1], data2)
        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data1)
    }
    
    @InMemoryActor
    func testInMemorySaveDifferentScopes() async {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        
        // When
        standardStorage.save(data1, forKey: key)

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key], data1)
        XCTAssertNil(InMemoryStorage.container["other"]?[key])

        // When
        otherStorage.save(data2, forKey: key)

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key], data1)
        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)

        // When
        standardStorage.save(data2, forKey: key)
        
        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key], data2)
        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)
    }
    
    @InMemoryActor
    func testInMemoryDelete() async {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        InMemoryStorage.container = [nil: [key1: data1, key2: data2]]
        
        // When
        standardStorage.delete(forKey: key1)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data2)

        // When
        standardStorage.delete(forKey: key1)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data2)

        // When
        standardStorage.delete(forKey: key2)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
        XCTAssertNil(InMemoryStorage.container[nil]?[key2])
    }
    
    @InMemoryActor
    func testInMemoryDeleteDifferentScopes() async {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        InMemoryStorage.container = [nil: [key: data1], "other": [key: data2]]
        
        // When
        standardStorage.delete(forKey: key)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key])
        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)

        // When
        standardStorage.delete(forKey: key)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key])
        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)

        // When
        otherStorage.delete(forKey: key)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key])
        XCTAssertNil(InMemoryStorage.container["other"]?[key])
    }
    
    @InMemoryActor
    func testInMemorySet() async {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        InMemoryStorage.container = [nil: [key1: data1, key2: data2]]
        
        // When
        standardStorage.set(data2, forKey: key1)

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key1], data2)
        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data2)

        // When
        standardStorage.set(nil, forKey: key1)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data2)
        
        // When
        standardStorage.set(data1, forKey: key2)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data1)
        
        // When
        standardStorage.set(nil, forKey: key2)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
        XCTAssertNil(InMemoryStorage.container[nil]?[key2])
    }
    
    @InMemoryActor
    func testInMemorySetDifferentScopes() async {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        InMemoryStorage.container = [nil: [key: data1], "other": [key: data2]]
        
        // When
        standardStorage.set(data2, forKey: key)

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key], data2)
        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)

        // When
        standardStorage.set(nil, forKey: key)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key])
        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)
        
        // When
        otherStorage.set(data1, forKey: key)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key])
        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data1)

        // When
        otherStorage.set(nil, forKey: key)

        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?[key])
        XCTAssertNil(InMemoryStorage.container["other"]?[key])
    }
    
    @InMemoryActor
    func testInMemoryClear() async {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        InMemoryStorage.container = [nil: [key1: data1, key2: data2], "other": [key1: data2, key2: data1]]
        
        // When
        standardStorage.clear()

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil], [:])
        XCTAssertEqual(InMemoryStorage.container["other"]?[key1], data2)
        XCTAssertEqual(InMemoryStorage.container["other"]?[key2], data1)

        // When
        standardStorage.clear()

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil], [:])
        XCTAssertEqual(InMemoryStorage.container["other"]?[key1], data2)
        XCTAssertEqual(InMemoryStorage.container["other"]?[key2], data1)
        
        // When
        InMemoryStorage.container = [nil: [key1: data1, key2: data2], "other": [key1: data2, key2: data1]]
        otherStorage.clear()

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil]?[key1], data1)
        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data2)
        XCTAssertEqual(InMemoryStorage.container["other"], [:])


        // When
        standardStorage.clear()

        // Then
        XCTAssertEqual(InMemoryStorage.container[nil], [:])
        XCTAssertEqual(InMemoryStorage.container["other"], [:])
    }
    
    func testThreadSafety() async {
        // Given
        let storage = standardStorage!
        let iterations = 5000
        
        // When
        await withTaskGroup(of: Void.self) { group in
            for _ in 1...iterations {
                let operation = Int.random(in: 0...4)
                let key = "\(Int.random(in: 1000...9999))"
                
                // Child tasks run in parallel on the shared thread pool, so the storage is called from many threads at once
                group.addTask {
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
                }
            }
            
            // Then: waiting for all of them finishes when they do, instead of a timeout guessing how long they take
            await group.waitForAll()
        }
    }
}
