//
//  UserDefaultsStorageTests.swift
//  
//
//  Created by Narek Sahakyan on 31.12.23.
//

import XCTest
import Foundation
@testable import UnifiedStorage

@UserDefaultsActor
final class UserDefaultsStorageTests: XCTestCase {
    static let otherStorageDomain = "other"
    var standardUserDefaults: UserDefaults!
    var otherUserDefaults: UserDefaults!
    var standardStorage: UserDefaultsStorage!
    var otherStorage: UserDefaultsStorage!
    
    override func setUpWithError() throws {
        standardUserDefaults = UserDefaults.standard
        otherUserDefaults = UserDefaults(suiteName: Self.otherStorageDomain)!
        
        standardUserDefaults.clearStandardStorage()
        otherUserDefaults.removePersistentDomain(forName: Self.otherStorageDomain)
        
        standardStorage = UserDefaultsStorage()
        otherStorage = try UserDefaultsStorage(domain: Self.otherStorageDomain)
    }
    
    func testUserDefaultsDomain() {
        XCTAssertEqual(standardStorage.domain, nil)
        XCTAssertEqual(otherStorage.domain, Self.otherStorageDomain)
    }
    
    func testUserDefaultsFetch() {
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
        standardUserDefaults.set(data1, forKey: key1)
        fetched1 = standardStorage.fetch(forKey: key1)
        fetched2 = standardStorage.fetch(forKey: key2)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertNil(fetched2)

        // When
        standardUserDefaults.set(data2, forKey: key1)
        fetched1 = standardStorage.fetch(forKey: key1)
        fetched2 = standardStorage.fetch(forKey: key2)

        // Then
        XCTAssertEqual(fetched1, data2)
        XCTAssertNil(fetched2)
        
        // When
        standardUserDefaults.set(data1, forKey: key1)
        standardUserDefaults.set(data2, forKey: key2)
        fetched1 = standardStorage.fetch(forKey: key1)
        fetched2 = standardStorage.fetch(forKey: key2)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertEqual(fetched2, data2)
        
        // When
        standardUserDefaults.set(data1, forKey: key2)
        standardUserDefaults.set(nil, forKey: key1)
        fetched1 = standardStorage.fetch(forKey: key1)
        fetched2 = standardStorage.fetch(forKey: key2)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertEqual(fetched2, data1)
        
        // When
        standardUserDefaults.clearStandardStorage()
        fetched1 = standardStorage.fetch(forKey: key1)
        fetched2 = standardStorage.fetch(forKey: key2)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
    }
    
    func testUserDefaultsFetchDifferentDomains() {
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
        standardUserDefaults.set(data1, forKey: key)
        fetched1 = standardStorage.fetch(forKey: key)
        fetched2 = otherStorage.fetch(forKey: key)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertNil(fetched2)

        // When
        standardUserDefaults.removeObject(forKey: key)
        otherUserDefaults.set(data2, forKey: key)
        fetched1 = standardStorage.fetch(forKey: key)
        fetched2 = otherStorage.fetch(forKey: key)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertEqual(fetched2, data2)

        // When
        standardUserDefaults.set(data2, forKey: key)
        otherUserDefaults.removeObject(forKey: key)
        fetched1 = standardStorage.fetch(forKey: key)
        fetched2 = otherStorage.fetch(forKey: key)

        // Then
        XCTAssertEqual(fetched1, data2)
        XCTAssertNil(fetched2)

        // When
        standardUserDefaults.set(data1, forKey: key)
        otherUserDefaults.set(data2, forKey: key)
        fetched1 = standardStorage.fetch(forKey: key)
        fetched2 = otherStorage.fetch(forKey: key)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertEqual(fetched2, data2)
        
        // When
        standardUserDefaults.removeObject(forKey: key)
        otherUserDefaults.removeObject(forKey: key)
        fetched1 = standardStorage.fetch(forKey: key)
        fetched2 = otherStorage.fetch(forKey: key)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
    }
    
    func testUserDefaultsSave() {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        
        // When
        standardStorage.save(data1, forKey: key1)

        // Then
        XCTAssertEqual(standardUserDefaults.data(forKey: key1), data1)
        XCTAssertNil(standardUserDefaults.data(forKey: key2))

        // When
        standardStorage.save(data2, forKey: key1)

        // Then
        XCTAssertEqual(standardUserDefaults.data(forKey: key1), data2)
        XCTAssertNil(standardUserDefaults.data(forKey: key2))

        // When
        standardStorage.save(data1, forKey: key2)
        
        // Then
        XCTAssertEqual(standardUserDefaults.data(forKey: key1), data2)
        XCTAssertEqual(standardUserDefaults.data(forKey: key2), data1)
    }
    
    func testUserDefaultsSaveDifferentDomains() {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        
        // When
        standardStorage.save(data1, forKey: key)

        // Then
        XCTAssertEqual(standardUserDefaults.data(forKey: key), data1)
        XCTAssertNil(otherUserDefaults.data(forKey: key))

        // When
        otherStorage.save(data2, forKey: key)

        // Then
        XCTAssertEqual(standardUserDefaults.data(forKey: key), data1)
        XCTAssertEqual(otherUserDefaults.data(forKey: key), data2)

        // When
        standardStorage.save(data2, forKey: key)
        
        // Then
        XCTAssertEqual(standardUserDefaults.data(forKey: key), data2)
        XCTAssertEqual(otherUserDefaults.data(forKey: key), data2)
    }
    
    func testUserDefaultsDelete() {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        standardUserDefaults.set(data1, forKey: key1)
        standardUserDefaults.set(data2, forKey: key2)
        
        // When
        standardStorage.delete(forKey: key1)

        // Then
        XCTAssertNil(standardUserDefaults.data(forKey: key1))
        XCTAssertEqual(standardUserDefaults.data(forKey: key2), data2)

        // When
        standardStorage.delete(forKey: key1)

        // Then
        XCTAssertNil(standardUserDefaults.data(forKey: key1))
        XCTAssertEqual(standardUserDefaults.data(forKey: key2), data2)

        // When
        standardStorage.delete(forKey: key2)

        // Then
        XCTAssertNil(standardUserDefaults.data(forKey: key1))
        XCTAssertNil(standardUserDefaults.data(forKey: key2))
    }
    
    func testUserDefaultsDeleteDifferentDomains() {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        standardUserDefaults.set(data1, forKey: key)
        otherUserDefaults.set(data2, forKey: key)
        
        // When
        standardStorage.delete(forKey: key)

        // Then
        XCTAssertNil(standardUserDefaults.data(forKey: key))
        XCTAssertEqual(otherUserDefaults.data(forKey: key), data2)

        // When
        standardStorage.delete(forKey: key)

        // Then
        XCTAssertNil(standardUserDefaults.data(forKey: key))
        XCTAssertEqual(otherUserDefaults.data(forKey: key), data2)

        // When
        otherStorage.delete(forKey: key)

        // Then
        XCTAssertNil(standardUserDefaults.data(forKey: key))
        XCTAssertNil(otherUserDefaults.data(forKey: key))
    }
    
    func testUserDefaultsSet() {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        standardUserDefaults.set(data1, forKey: key1)
        standardUserDefaults.set(data2, forKey: key2)
        
        // When
        standardStorage.set(data2, forKey: key1)

        // Then
        XCTAssertEqual(standardUserDefaults.data(forKey: key1), data2)
        XCTAssertEqual(standardUserDefaults.data(forKey: key2), data2)

        // When
        standardStorage.set(nil, forKey: key1)

        // Then
        XCTAssertNil(standardUserDefaults.data(forKey: key1))
        XCTAssertEqual(standardUserDefaults.data(forKey: key2), data2)
        
        // When
        standardStorage.set(data1, forKey: key2)

        // Then
        XCTAssertNil(standardUserDefaults.data(forKey: key1))
        XCTAssertEqual(standardUserDefaults.data(forKey: key2), data1)
        
        // When
        standardStorage.set(nil, forKey: key2)

        // Then
        XCTAssertNil(standardUserDefaults.data(forKey: key1))
        XCTAssertNil(standardUserDefaults.data(forKey: key2))
    }
    
    func testUserDefaultsSetDifferentDomains() {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        standardUserDefaults.set(data1, forKey: key)
        otherUserDefaults.set(data2, forKey: key)
        
        // When
        standardStorage.set(data2, forKey: key)

        // Then
        XCTAssertEqual(standardUserDefaults.data(forKey: key), data2)
        XCTAssertEqual(otherUserDefaults.data(forKey: key), data2)

        // When
        standardStorage.set(nil, forKey: key)

        // Then
        XCTAssertNil(standardUserDefaults.data(forKey: key))
        XCTAssertEqual(otherUserDefaults.data(forKey: key), data2)
        
        // When
        otherStorage.set(data1, forKey: key)

        // Then
        XCTAssertNil(standardUserDefaults.data(forKey: key))
        XCTAssertEqual(otherUserDefaults.data(forKey: key), data1)

        // When
        otherStorage.set(nil, forKey: key)

        // Then
        XCTAssertNil(standardUserDefaults.data(forKey: key))
        XCTAssertNil(otherUserDefaults.data(forKey: key))
    }
    
    func testUserDefaultsClear() {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        standardUserDefaults.set(data1, forKey: key1)
        standardUserDefaults.set(data2, forKey: key2)
        otherUserDefaults.set(data1, forKey: key1)
        otherUserDefaults.set(data2, forKey: key2)
        
        // When
        standardStorage.clear()

        // Then
        XCTAssertNil(standardUserDefaults.data(forKey: key1))
        XCTAssertNil(standardUserDefaults.data(forKey: key2))
        XCTAssertEqual(otherUserDefaults.data(forKey: key1), data1)
        XCTAssertEqual(otherUserDefaults.data(forKey: key2), data2)
        
        // When
        standardStorage.clear()

        // Then
        XCTAssertNil(standardUserDefaults.data(forKey: key1))
        XCTAssertNil(standardUserDefaults.data(forKey: key2))
        XCTAssertEqual(otherUserDefaults.data(forKey: key1), data1)
        XCTAssertEqual(otherUserDefaults.data(forKey: key2), data2)
        
        // When
        standardUserDefaults.set(data2, forKey: key1)
        standardUserDefaults.set(data1, forKey: key2)
        otherStorage.clear()

        // Then
        XCTAssertEqual(standardUserDefaults.data(forKey: key1), data2)
        XCTAssertEqual(standardUserDefaults.data(forKey: key2), data1)
        XCTAssertNil(otherUserDefaults.data(forKey: key1))
        XCTAssertNil(otherUserDefaults.data(forKey: key2))

        // When
        standardStorage.clear()

        // Then
        XCTAssertNil(standardUserDefaults.data(forKey: key1))
        XCTAssertNil(standardUserDefaults.data(forKey: key2))
        XCTAssertNil(otherUserDefaults.data(forKey: key1))
        XCTAssertNil(otherUserDefaults.data(forKey: key2))
    }
    
    func testThreadSafety() {
        // Given
        let iterations = 5000
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
                    _ = await self.standardStorage.fetch(forKey: key)
                case 1:
                    await self.standardStorage.save(.init(), forKey: key)
                case 2:
                    await self.standardStorage.delete(forKey: key)
                case 3:
                    await self.standardStorage.set(Bool.random() ? nil : .init(), forKey: key)
                case 4:
                    await self.standardStorage.clear()
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

