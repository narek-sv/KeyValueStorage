//
//  KeychainStorageTests.swift
//
//
//  Created by Narek Sahakyan on 31.12.23.
//

import XCTest
import Foundation
@testable import UnifiedStorage

@KeychainActor
final class KeychainStorageTests: XCTestCase {
    static let otherStorageDomain = KeychainStorage.Domain(groupId: "xxx", teamId: "yyy")
    var standardKeychain: KeychainHelper!
    var otherKeychain: KeychainHelper!
    var standardStorage: KeychainStorage!
    var otherStorage: KeychainStorage!
    
    override func setUpWithError() throws {
        standardKeychain = KeychainHelper(serviceName: Bundle.main.bundleIdentifier!)
        otherKeychain = KeychainHelper(serviceName: Bundle.main.bundleIdentifier!, accessGroup: Self.otherStorageDomain.accessGroup)

        try standardKeychain.removeAll()
        try otherKeychain.removeAll()
        
        standardStorage = KeychainStorage()
        otherStorage = KeychainStorage(domain: Self.otherStorageDomain)
        
    }
    
    func testKeychainDomain() {
        XCTAssertEqual(standardStorage.domain, nil)
        XCTAssertEqual(otherStorage.domain, Self.otherStorageDomain)
    }
    
    func testKeychainFetch() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        let storageKey1 = KeychainStorage.Key(name: key1)
        let storageKey2 = KeychainStorage.Key(name: key2)
        
        // When
        var fetched1 = try standardStorage.fetch(forKey: storageKey1)
        var fetched2 = try standardStorage.fetch(forKey: storageKey2)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)

        // When
        try standardKeychain.set(data1, forKey: key1)
        fetched1 = try standardStorage.fetch(forKey: storageKey1)
        fetched2 = try standardStorage.fetch(forKey: storageKey2)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertNil(fetched2)

        // When
        try standardKeychain.set(data2, forKey: key1)
        fetched1 = try standardStorage.fetch(forKey: storageKey1)
        fetched2 = try standardStorage.fetch(forKey: storageKey2)

        // Then
        XCTAssertEqual(fetched1, data2)
        XCTAssertNil(fetched2)
        
        // When
        try standardKeychain.set(data1, forKey: key1)
        try standardKeychain.set(data2, forKey: key2)
        fetched1 = try standardStorage.fetch(forKey: storageKey1)
        fetched2 = try standardStorage.fetch(forKey: storageKey2)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertEqual(fetched2, data2)
        
        // When
        try standardKeychain.set(data1, forKey: key2)
        try standardKeychain.remove(forKey: key1)
        fetched1 = try standardStorage.fetch(forKey: storageKey1)
        fetched2 = try standardStorage.fetch(forKey: storageKey2)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertEqual(fetched2, data1)
        
        // When
        try standardKeychain.removeAll()
        fetched1 = try standardStorage.fetch(forKey: storageKey1)
        fetched2 = try standardStorage.fetch(forKey: storageKey2)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
    }
    
    func testKeychainFetchDifferentDomains() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        let storageKey = KeychainStorage.Key(name: key)
        try standardKeychain.removeAll()
        try otherKeychain.removeAll()

        // When
        var fetched1 = try standardStorage.fetch(forKey: storageKey)
        var fetched2 = try otherStorage.fetch(forKey: storageKey)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)

        // When
        try standardKeychain.set(data1, forKey: key)
        fetched1 = try standardStorage.fetch(forKey: storageKey)
        fetched2 = try otherStorage.fetch(forKey: storageKey)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertNil(fetched2)

        // When
        try standardKeychain.remove(forKey: key)
        try otherKeychain.set(data2, forKey: key)
        fetched1 = try standardStorage.fetch(forKey: storageKey)
        fetched2 = try otherStorage.fetch(forKey: storageKey)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertEqual(fetched2, data2)

        // When
        try standardKeychain.set(data2, forKey: key)
        try otherKeychain.remove(forKey: key)
        fetched1 = try standardStorage.fetch(forKey: storageKey)
        fetched2 = try otherStorage.fetch(forKey: storageKey)

        // Then
        XCTAssertEqual(fetched1, data2)
        XCTAssertNil(fetched2)

        // When
        try standardKeychain.set(data1, forKey: key)
        try otherKeychain.set(data2, forKey: key)
        fetched1 = try standardStorage.fetch(forKey: storageKey)
        fetched2 = try otherStorage.fetch(forKey: storageKey)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertEqual(fetched2, data2)
        
        // When
        try standardKeychain.remove(forKey: key)
        try otherKeychain.remove(forKey: key)
        fetched1 = try standardStorage.fetch(forKey: storageKey)
        fetched2 = try otherStorage.fetch(forKey: storageKey)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
    }
    
    func testKeychainSave() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        let storageKey1 = KeychainStorage.Key(name: key1)
        let storageKey2 = KeychainStorage.Key(name: key2)
        
        // When
        try standardStorage.save(data1, forKey: storageKey1)

        // Then
        XCTAssertEqual(try standardKeychain.get(forKey: key1), data1)
        XCTAssertNil(try standardKeychain.get(forKey: key2))

        // When
        try standardStorage.save(data2, forKey: storageKey1)

        // Then
        XCTAssertEqual(try standardKeychain.get(forKey: key1), data2)
        XCTAssertNil(try standardKeychain.get(forKey: key2))

        // When
        try standardStorage.save(data1, forKey: storageKey2)
        
        // Then
        XCTAssertEqual(try standardKeychain.get(forKey: key1), data2)
        XCTAssertEqual(try standardKeychain.get(forKey: key2), data1)
    }
    
    func testKeychainSaveDifferentDomains() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        let storageKey = KeychainStorage.Key(name: key)
        
        // When
        try standardStorage.save(data1, forKey: storageKey)

        // Then
        XCTAssertEqual(try standardKeychain.get(forKey: key), data1)
        XCTAssertNil(try otherKeychain.get(forKey: key))

        // When
        try otherStorage.save(data2, forKey: storageKey)

        // Then
        XCTAssertEqual(try standardKeychain.get(forKey: key), data1)
        XCTAssertEqual(try otherKeychain.get(forKey: key), data2)

        // When
        try standardStorage.save(data2, forKey: storageKey)
        
        // Then
        XCTAssertEqual(try standardKeychain.get(forKey: key), data2)
        XCTAssertEqual(try otherKeychain.get(forKey: key), data2)
    }
    
    func testKeychainDelete() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        let storageKey1 = KeychainStorage.Key(name: key1)
        let storageKey2 = KeychainStorage.Key(name: key2)
        try standardKeychain.set(data1, forKey: key1)
        try standardKeychain.set(data2, forKey: key2)
        
        // When
        try standardStorage.delete(forKey: storageKey1)

        // Then
        XCTAssertNil(try standardKeychain.get(forKey: key1))
        XCTAssertEqual(try standardKeychain.get(forKey: key2), data2)

        // When
        try standardStorage.delete(forKey: storageKey1)

        // Then
        XCTAssertNil(try standardKeychain.get(forKey: key1))
        XCTAssertEqual(try standardKeychain.get(forKey: key2), data2)

        // When
        try standardStorage.delete(forKey: storageKey2)

        // Then
        XCTAssertNil(try standardKeychain.get(forKey: key1))
        XCTAssertNil(try standardKeychain.get(forKey: key2))
    }
    
    func testKeychainDeleteDifferentDomains() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        let storageKey = KeychainStorage.Key(name: key)
        try standardKeychain.set(data1, forKey: key)
        try otherKeychain.set(data2, forKey: key)
        
        // When
        try standardStorage.delete(forKey: storageKey)

        // Then
        XCTAssertNil(try standardKeychain.get(forKey: key))
        XCTAssertEqual(try otherKeychain.get(forKey: key), data2)

        // When
        try standardStorage.delete(forKey: storageKey)

        // Then
        XCTAssertNil(try standardKeychain.get(forKey: key))
        XCTAssertEqual(try otherKeychain.get(forKey: key), data2)

        // When
        try otherStorage.delete(forKey: storageKey)

        // Then
        XCTAssertNil(try standardKeychain.get(forKey: key))
        XCTAssertNil(try otherKeychain.get(forKey: key))
    }
    
    func testKeychainSet() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        let storageKey1 = KeychainStorage.Key(name: key1)
        let storageKey2 = KeychainStorage.Key(name: key2)
        try standardKeychain.set(data1, forKey: key1)
        try standardKeychain.set(data2, forKey: key2)
        
        // When
        try standardStorage.set(data2, forKey: storageKey1)

        // Then
        XCTAssertEqual(try standardKeychain.get(forKey: key1), data2)
        XCTAssertEqual(try standardKeychain.get(forKey: key2), data2)

        // When
        try standardStorage.set(nil, forKey: storageKey1)

        // Then
        XCTAssertNil(try standardKeychain.get(forKey: key1))
        XCTAssertEqual(try standardKeychain.get(forKey: key2), data2)
        
        // When
        try standardStorage.set(data1, forKey: storageKey2)

        // Then
        XCTAssertNil(try standardKeychain.get(forKey: key1))
        XCTAssertEqual(try standardKeychain.get(forKey: key2), data1)
        
        // When
        try standardStorage.set(nil, forKey: storageKey2)

        // Then
        XCTAssertNil(try standardKeychain.get(forKey: key1))
        XCTAssertNil(try standardKeychain.get(forKey: key2))
    }
    
    func testKeychainSetDifferentDomains() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        let storageKey = KeychainStorage.Key(name: key)
        try standardKeychain.set(data1, forKey: key)
        try otherKeychain.set(data2, forKey: key)
        
        // When
        try standardStorage.set(data2, forKey: storageKey)

        // Then
        XCTAssertEqual(try standardKeychain.get(forKey: key), data2)
        XCTAssertEqual(try otherKeychain.get(forKey: key), data2)

        // When
        try standardStorage.set(nil, forKey: storageKey)

        // Then
        XCTAssertNil(try standardKeychain.get(forKey: key))
        XCTAssertEqual(try otherKeychain.get(forKey: key), data2)
        
        // When
        try otherStorage.set(data1, forKey: storageKey)

        // Then
        XCTAssertNil(try standardKeychain.get(forKey: key))
        XCTAssertEqual(try otherKeychain.get(forKey: key), data1)

        // When
        try otherStorage.set(nil, forKey: storageKey)

        // Then
        XCTAssertNil(try standardKeychain.get(forKey: key))
        XCTAssertNil(try otherKeychain.get(forKey: key))
    }
    
    func testKeychainClear() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        try standardKeychain.set(data1, forKey: key1)
        try standardKeychain.set(data2, forKey: key2)
        try otherKeychain.set(data1, forKey: key1)
        try otherKeychain.set(data2, forKey: key2)
        
        // When
        try standardStorage.clear()

        // Then
        XCTAssertNil(try standardKeychain.get(forKey: key1))
        XCTAssertNil(try standardKeychain.get(forKey: key2))
        XCTAssertEqual(try otherKeychain.get(forKey: key1), data1)
        XCTAssertEqual(try otherKeychain.get(forKey: key2), data2)
        
        // When
        try standardStorage.clear()

        // Then
        XCTAssertNil(try standardKeychain.get(forKey: key1))
        XCTAssertNil(try standardKeychain.get(forKey: key2))
        XCTAssertEqual(try otherKeychain.get(forKey: key1), data1)
        XCTAssertEqual(try otherKeychain.get(forKey: key2), data2)
        
        // When
        try standardKeychain.set(data2, forKey: key1)
        try standardKeychain.set(data1, forKey: key2)
        try otherStorage.clear()

        // Then
        XCTAssertEqual(try standardKeychain.get(forKey: key1), data2)
        XCTAssertEqual(try standardKeychain.get(forKey: key2), data1)
        XCTAssertNil(try otherKeychain.get(forKey: key1))
        XCTAssertNil(try otherKeychain.get(forKey: key2))

        // When
        try standardStorage.clear()

        // Then
        XCTAssertNil(try standardKeychain.get(forKey: key1))
        XCTAssertNil(try standardKeychain.get(forKey: key2))
        XCTAssertNil(try otherKeychain.get(forKey: key1))
        XCTAssertNil(try otherKeychain.get(forKey: key2))
    }
    
    func testThreadSafety() throws {
        // Given
        let iterations = 5000
        let promise = expectation(description: "testThreadSafety")
        let group = DispatchGroup()
        for _ in 1...iterations { group.enter() }
        
        // When
        DispatchQueue.concurrentPerform(iterations: iterations) { number in
            let operation = Int.random(in: 0...4)
            let key = KeychainStorage.Key(name: "\(Int.random(in: 1000...9999))")
            
            Task.detached {
                do {
                    switch operation {
                    case 0:
                        _ = try await self.standardStorage.fetch(forKey: key)
                    case 1:
                        try await self.standardStorage.save(.init(), forKey: key)
                    case 2:
                        try await self.standardStorage.delete(forKey: key)
                    case 3:
                        try await self.standardStorage.set(Bool.random() ? nil : .init(), forKey: key)
                    case 4:
                        try await self.standardStorage.clear()
                    default:
                        break
                    }
                } catch {
                    XCTFail("Unexpected error")
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
