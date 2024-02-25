//
//  UnifiedStorageTests.swift
//
//
//  Created by Narek Sahakyan on 12.12.23.
//

import XCTest
import Foundation
@testable import UnifiedStorage

//@UserDefaultsActor
@UserDefaultsActor
final class UnifiedStorageTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.clearStandardStorage()
        UserDefaults(suiteName: "other")?.removePersistentDomain(forName: "other")
    }
    
    func testUserDefaultsDomain() throws {
        // Given
        let storage1 = UserDefaultsStorage()
        let storage2 = try UserDefaultsStorage(domain: "other")
        
        // When - Then
        XCTAssertEqual(storage1.domain, nil)
        XCTAssertEqual(storage2.domain, "other")
    }
    
    func testUserDefaultsFetch() throws {
        // Given
        let standardStorage = UserDefaults.standard
        let storage = UserDefaultsStorage()
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        standardStorage.clearStandardStorage()
        
        // When
        var fetched1 = storage.fetch(forKey: key1)
        var fetched2 = storage.fetch(forKey: key2)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)

        // When
        standardStorage.set(data1, forKey: key1)
        fetched1 = storage.fetch(forKey: key1)
        fetched2 = storage.fetch(forKey: key2)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertNil(fetched2)

        // When
        standardStorage.set(data2, forKey: key1)
        fetched1 = storage.fetch(forKey: key1)
        fetched2 = storage.fetch(forKey: key2)

        // Then
        XCTAssertEqual(fetched1, data2)
        XCTAssertNil(fetched2)
        
        // When
        standardStorage.set(data1, forKey: key1)
        standardStorage.set(data2, forKey: key2)
        fetched1 = storage.fetch(forKey: key1)
        fetched2 = storage.fetch(forKey: key2)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertEqual(fetched2, data2)
        
        // When
        standardStorage.set(data1, forKey: key2)
        standardStorage.set(nil, forKey: key1)
        fetched1 = storage.fetch(forKey: key1)
        fetched2 = storage.fetch(forKey: key2)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertEqual(fetched2, data1)
        
        // When
        standardStorage.clearStandardStorage()
        fetched1 = storage.fetch(forKey: key1)
        fetched2 = storage.fetch(forKey: key2)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
    }
    
    func testUserDefaultsFetchDifferentDomains() throws {
        // Given
        let standardStorage = UserDefaults.standard
        let otherStorage = UserDefaults(suiteName: "other")!
        let storage1 = UserDefaultsStorage()
        let storage2 = try UserDefaultsStorage(domain: "other")
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        standardStorage.clearStandardStorage()
        otherStorage.removePersistentDomain(forName: "other")

        // When
        var fetched1 = storage1.fetch(forKey: key)
        var fetched2 = storage2.fetch(forKey: key)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)

        // When
        standardStorage.set(data1, forKey: key)
        fetched1 = storage1.fetch(forKey: key)
        fetched2 = storage2.fetch(forKey: key)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertNil(fetched2)

        // When
        standardStorage.removeObject(forKey: key)
        otherStorage.set(data2, forKey: key)
        fetched1 = storage1.fetch(forKey: key)
        fetched2 = storage2.fetch(forKey: key)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertEqual(fetched2, data2)

        // When
        standardStorage.set(data2, forKey: key)
        otherStorage.removeObject(forKey: key)
        fetched1 = storage1.fetch(forKey: key)
        fetched2 = storage2.fetch(forKey: key)

        // Then
        XCTAssertEqual(fetched1, data2)
        XCTAssertNil(fetched2)

        // When
        standardStorage.set(data1, forKey: key)
        otherStorage.set(data2, forKey: key)
        fetched1 = storage1.fetch(forKey: key)
        fetched2 = storage2.fetch(forKey: key)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertEqual(fetched2, data2)
        
        // When
        standardStorage.removeObject(forKey: key)
        otherStorage.removeObject(forKey: key)
        fetched1 = storage1.fetch(forKey: key)
        fetched2 = storage2.fetch(forKey: key)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
    }
    
    func testUserDefaultsSave() throws {
        // Given
        let standardStorage = UserDefaults.standard
        let storage = UserDefaultsStorage()
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        
        // When
        storage.save(data1, forKey: key1)

        // Then
        XCTAssertEqual(standardStorage.data(forKey: key1), data1)
        XCTAssertNil(standardStorage.data(forKey: key2))

        // When
        storage.save(data2, forKey: key1)

        // Then
        XCTAssertEqual(standardStorage.data(forKey: key1), data2)
        XCTAssertNil(standardStorage.data(forKey: key2))

        // When
        storage.save(data1, forKey: key2)
        
        // Then
        XCTAssertEqual(standardStorage.data(forKey: key1), data2)
        XCTAssertEqual(standardStorage.data(forKey: key2), data1)
    }
    
    func testUserDefaultsSaveDifferentDomains() throws {
        // Given
        let standardStorage = UserDefaults.standard
        let otherStorage = UserDefaults(suiteName: "other")!
        let storage1 = UserDefaultsStorage()
        let storage2 = try UserDefaultsStorage(domain: "other")
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        
        // When
        storage1.save(data1, forKey: key)

        // Then
        XCTAssertEqual(standardStorage.data(forKey: key), data1)
        XCTAssertNil(otherStorage.data(forKey: key))

        // When
        storage2.save(data2, forKey: key)

        // Then
        XCTAssertEqual(standardStorage.data(forKey: key), data1)
        XCTAssertEqual(otherStorage.data(forKey: key), data2)

        // When
        storage1.save(data2, forKey: key)
        
        // Then
        XCTAssertEqual(standardStorage.data(forKey: key), data2)
        XCTAssertEqual(otherStorage.data(forKey: key), data2)
    }
    
    func testUserDefaultsDelete() throws {
        // Given
        let standardStorage = UserDefaults.standard
        let storage = UserDefaultsStorage()
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        standardStorage.set(data1, forKey: key1)
        standardStorage.set(data2, forKey: key2)
        
        // When
        storage.delete(forKey: key1)

        // Then
        XCTAssertNil(standardStorage.data(forKey: key1))
        XCTAssertEqual(standardStorage.data(forKey: key2), data2)

        // When
        storage.delete(forKey: key1)

        // Then
        XCTAssertNil(standardStorage.data(forKey: key1))
        XCTAssertEqual(standardStorage.data(forKey: key2), data2)

        // When
        storage.delete(forKey: key2)

        // Then
        XCTAssertNil(standardStorage.data(forKey: key1))
        XCTAssertNil(standardStorage.data(forKey: key2))
    }
    
    func testUserDefaultsDeleteDifferentDomains() throws {
        // Given
        let standardStorage = UserDefaults.standard
        let otherStorage = UserDefaults(suiteName: "other")!
        let storage1 = UserDefaultsStorage()
        let storage2 = try UserDefaultsStorage(domain: "other")
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        standardStorage.set(data1, forKey: key)
        otherStorage.set(data2, forKey: key)
        
        // When
        storage1.delete(forKey: key)

        // Then
        XCTAssertNil(standardStorage.data(forKey: key))
        XCTAssertEqual(otherStorage.data(forKey: key), data2)

        // When
        storage1.delete(forKey: key)

        // Then
        XCTAssertNil(standardStorage.data(forKey: key))
        XCTAssertEqual(otherStorage.data(forKey: key), data2)

        // When
        storage2.delete(forKey: key)

        // Then
        XCTAssertNil(standardStorage.data(forKey: key))
        XCTAssertNil(otherStorage.data(forKey: key))
    }
    
    func testUserDefaultsSet() throws {
        // Given
        let standardStorage = UserDefaults.standard
        let storage = UserDefaultsStorage()
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        standardStorage.set(data1, forKey: key1)
        standardStorage.set(data2, forKey: key2)
        
        // When
        storage.set(data2, forKey: key1)

        // Then
        XCTAssertEqual(standardStorage.data(forKey: key1), data2)
        XCTAssertEqual(standardStorage.data(forKey: key2), data2)

        // When
        storage.set(nil, forKey: key1)

        // Then
        XCTAssertNil(standardStorage.data(forKey: key1))
        XCTAssertEqual(standardStorage.data(forKey: key2), data2)
        
        // When
        storage.set(data1, forKey: key2)

        // Then
        XCTAssertNil(standardStorage.data(forKey: key1))
        XCTAssertEqual(standardStorage.data(forKey: key2), data1)
        
        // When
        storage.set(nil, forKey: key2)

        // Then
        XCTAssertNil(standardStorage.data(forKey: key1))
        XCTAssertNil(standardStorage.data(forKey: key2))
    }
    
    func testUserDefaultsSetDifferentDomains() throws {
        // Given
        let standardStorage = UserDefaults.standard
        let otherStorage = UserDefaults(suiteName: "other")!
        let storage1 = UserDefaultsStorage()
        let storage2 = try UserDefaultsStorage(domain: "other")
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        standardStorage.set(data1, forKey: key)
        otherStorage.set(data2, forKey: key)
        
        // When
        storage1.set(data2, forKey: key)

        // Then
        XCTAssertEqual(standardStorage.data(forKey: key), data2)
        XCTAssertEqual(otherStorage.data(forKey: key), data2)

        // When
        storage1.set(nil, forKey: key)

        // Then
        XCTAssertNil(standardStorage.data(forKey: key))
        XCTAssertEqual(otherStorage.data(forKey: key), data2)
        
        // When
        storage2.set(data1, forKey: key)

        // Then
        XCTAssertNil(standardStorage.data(forKey: key))
        XCTAssertEqual(otherStorage.data(forKey: key), data1)

        // When
        storage2.set(nil, forKey: key)

        // Then
        XCTAssertNil(standardStorage.data(forKey: key))
        XCTAssertNil(otherStorage.data(forKey: key))
    }
    
    func testInMemoryClear() throws {
        // Given
        let standardStorage = UserDefaults.standard
        let otherStorage = UserDefaults(suiteName: "other")!
        let storage1 = UserDefaultsStorage()
        let storage2 = try UserDefaultsStorage(domain: "other")
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        standardStorage.set(data1, forKey: key1)
        standardStorage.set(data2, forKey: key2)
        otherStorage.set(data1, forKey: key1)
        otherStorage.set(data2, forKey: key2)
        
        // When
        storage1.clear()

        // Then
        XCTAssertNil(standardStorage.data(forKey: key1))
        XCTAssertNil(standardStorage.data(forKey: key2))
        XCTAssertEqual(otherStorage.data(forKey: key1), data1)
        XCTAssertEqual(otherStorage.data(forKey: key2), data2)
        
        // When
        storage1.clear()

        // Then
        XCTAssertNil(standardStorage.data(forKey: key1))
        XCTAssertNil(standardStorage.data(forKey: key2))
        XCTAssertEqual(otherStorage.data(forKey: key1), data1)
        XCTAssertEqual(otherStorage.data(forKey: key2), data2)
        
        // When
        standardStorage.set(data2, forKey: key1)
        standardStorage.set(data1, forKey: key2)
        storage2.clear()

        // Then
        XCTAssertEqual(standardStorage.data(forKey: key1), data2)
        XCTAssertEqual(standardStorage.data(forKey: key2), data1)
        XCTAssertNil(otherStorage.data(forKey: key1))
        XCTAssertNil(otherStorage.data(forKey: key2))

        // When
        storage1.clear()

        // Then
        XCTAssertNil(standardStorage.data(forKey: key1))
        XCTAssertNil(standardStorage.data(forKey: key2))
        XCTAssertNil(otherStorage.data(forKey: key1))
        XCTAssertNil(otherStorage.data(forKey: key2))
    }
    
    func testThreadSafety() throws {
        // Given
        let iterations = 5000
        let storage = UserDefaultsStorage()
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

extension UserDefaults {
    func clearStandardStorage() {
        self.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
    }
}
