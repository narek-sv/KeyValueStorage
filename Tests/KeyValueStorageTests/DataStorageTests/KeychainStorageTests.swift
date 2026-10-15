//
//  KeychainStorageTests.swift
//
//
//  Created by Narek Sahakyan on 31.12.23.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class KeychainStorageTests: XCTestCase {
    static let otherStorageDomain = KeychainStorage.Domain(groupId: "xxx", teamId: "yyy")
    var standardKeychain: KeychainWrapper!
    var otherKeychain: KeychainWrapper!
    var standardStorage: KeychainStorage!
    var otherStorage: KeychainStorage!
    
    #if SWIFT_PACKAGE_CAN_ATTACH_ENTITLEMENTS
    
    @KeychainActor
    override func setUp() async throws {
        standardKeychain = KeychainWrapper(serviceName: KeychainStorage.defaultService)
        otherKeychain = KeychainWrapper(serviceName: Self.otherStorageDomain.service, accessGroup: Self.otherStorageDomain.accessGroup)

        try standardKeychain.removeAll()
        try otherKeychain.removeAll()
        
        standardStorage = KeychainStorage()
        otherStorage = KeychainStorage(domain: Self.otherStorageDomain)
        
    }
    
    @KeychainActor
    func testKeychainDomain() async {
        XCTAssertEqual(standardStorage.domain, nil)
        XCTAssertEqual(otherStorage.domain, Self.otherStorageDomain)
    }
    
    @KeychainActor
    func testKeychainFetch() async throws {
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
    
    @KeychainActor
    func testKeychainFetchDifferentDomains() async throws {
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
    
    @KeychainActor
    func testKeychainSave() async throws {
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
    
    @KeychainActor
    func testKeychainSaveDifferentDomains() async throws {
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
    
    @KeychainActor
    func testKeychainDelete() async throws {
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
    
    @KeychainActor
    func testKeychainDeleteDifferentDomains() async throws {
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
    
    @KeychainActor
    func testKeychainSet() async throws {
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
    
    @KeychainActor
    func testKeychainSetDifferentDomains() async throws {
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
    
    @KeychainActor
    func testKeychainClear() async throws {
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
    
    @KeychainActor
    func testErrorCaseAccessGroupWithoutEntitlement() async throws {
        // Given: sharing through an access group the app isn't entitled to, a common keychain sharing mistake
        let storage = KeychainStorage(domain: .init(accessGroup: "not.entitled"))
        let key = KeychainStorage.Key(name: "key")
        
        // When - Then: the keychain's error is reported instead of a missing value
        XCTAssertThrowsError(try storage.fetch(forKey: key)) { assertMissingEntitlement($0) }
        XCTAssertThrowsError(try storage.save(Data([0xAA]), forKey: key)) { assertMissingEntitlement($0) }
        XCTAssertThrowsError(try storage.delete(forKey: key)) { assertMissingEntitlement($0) }
        XCTAssertThrowsError(try storage.clear()) { assertMissingEntitlement($0) }
    }
    
    private func assertMissingEntitlement(_ error: Error, line: UInt = #line) {
        guard case let .os(status) = error as? KeychainStorage.Error else {
            return XCTFail("Unexpected error \(error)", line: line)
        }
        
        XCTAssertEqual(status, errSecMissingEntitlement, line: line)
    }
    
    func testThreadSafety() async throws {
        // Given
        let storage = standardStorage!
        let iterations = 5000
        
        // When
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 1...iterations {
                let operation = Int.random(in: 0...4)
                let key = KeychainStorage.Key(name: "\(Int.random(in: 1000...9999))")
                
                // Child tasks run in parallel on the shared thread pool, so the storage is called from many threads at once
                group.addTask {
                    switch operation {
                    case 0:
                        _ = try await storage.fetch(forKey: key)
                    case 1:
                        try await storage.save(.init(), forKey: key)
                    case 2:
                        try await storage.delete(forKey: key)
                    case 3:
                        try await storage.set(Bool.random() ? nil : .init(), forKey: key)
                    case 4:
                        try await storage.clear()
                    default:
                        break
                    }
                }
            }
            
            // Then: waiting for all of them rethrows the first error, instead of a timeout guessing how long they take
            try await group.waitForAll()
        }
    }
    
    #endif
    
    @KeychainActor
    func testDomain() async {
        // Given
        var domain = KeychainStorage.Domain(groupId: "a", teamId: "b")
        
        // When
        let group = domain.accessGroup
        
        // Then
        XCTAssertEqual(group, "b.a")
        XCTAssertEqual(KeychainStorage.defaultService, "KeyValueStorage")
        XCTAssertEqual(domain.service, "KeyValueStorage.b.a")
        XCTAssertNotEqual(domain.service, KeychainStorage.defaultService)
        XCTAssertEqual(domain, KeychainStorage.Domain(accessGroup: "b.a"))
        
        // When
        domain = KeychainStorage.Domain(groupId: "a", teamId: "b", service: "custom")
        
        // Then
        XCTAssertEqual(domain.service, "custom")
        XCTAssertNotEqual(domain, KeychainStorage.Domain(groupId: "a", teamId: "b"))
    }
    
    @KeychainActor
    func testAppGroupDomain() async {
        // Given
        let domain = KeychainStorage.Domain(accessGroup: "group.com.company.app")
        
        // Then
        XCTAssertEqual(domain.accessGroup, "group.com.company.app")
        XCTAssertEqual(domain.service, "KeyValueStorage.group.com.company.app")
        XCTAssertEqual(KeychainStorage.Domain(accessGroup: "group.com.company.app", service: "custom").service, "custom")
    }
    
    @KeychainActor
    func testInitDomains() async {
        // When
        var storage = KeychainStorage()
        
        // Then
        XCTAssertNil(storage.domain)
        
        // When
        storage = KeychainStorage(domain: .init(groupId: "a", teamId: "b"))
        
        // Then
        XCTAssertEqual(storage.domain, .init(groupId: "a", teamId: "b"))
    }
    
    @KeychainActor
    func testInitCustomKeychain() async {
        // Given
        let keychain = KeychainWrapper(serviceName: "mock")
        
        // When
        let storage = KeychainStorage(keychain: keychain)
        
        // Then
        XCTAssertNil(storage.domain)
    }
    
    func testWrapperItemQueryIgnoresAccessibility() {
        // Given
        let keychain = KeychainWrapper(serviceName: "service", accessGroup: "group")
        
        // When
        let query = keychain.query(forKey: "key", isSynchronizable: true)
        
        // Then
        XCTAssertNil(query[kSecAttrAccessible as String])
        XCTAssertNil(query[kSecValueData as String])
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "key")
        XCTAssertEqual(query[kSecAttrService as String] as? String, "service")
        XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, "group")
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, true)
        XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
    }
    
    func testWrapperAttributesApplyAccessibility() {
        // Given
        let keychain = KeychainWrapper(serviceName: "service")
        let data = Data([0xAA, 0xBB, 0xCC])
        
        // When
        var attributes = keychain.attributes(for: data, withAccessibility: .afterFirstUnlock)
        
        // Then
        XCTAssertEqual(attributes[kSecValueData as String] as? Data, data)
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlock as String)
        
        // When
        attributes = keychain.attributes(for: data, withAccessibility: nil)
        
        // Then
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlocked as String)
    }
    
    func testWrapperRemoveAllQueryMatchesEveryItemOfTheService() {
        // Given
        let keychain = KeychainWrapper(serviceName: "service", accessGroup: "group")
        
        // When
        let query = keychain.removeAllQuery()
        
        // Then
        XCTAssertNil(query[kSecAttrAccount as String])
        XCTAssertEqual(query[kSecAttrService as String] as? String, "service")
        XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, "group")
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? String, kSecAttrSynchronizableAny as String)
        XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
    }
    
    @KeychainActor
    func testMockedFetch() async {
        // Given
        let mock = KeychainHelperMock(serviceName: "mock")
        let storage = KeychainStorage(keychain: mock)
        mock.getError = KeychainWrapperError.status(.max)

        do {
            // When
            _ = try storage.fetch(forKey: .init(name: "nonExistingFile"))
        } catch let error as KeychainStorage.Error {
            // Then
            if case .os(.max) = error {
                // ok
            } else {
                XCTFail("Unexpected error")
            }
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
        
        // Given
        mock.getError = CocoaError(CocoaError.fileNoSuchFile)
        
        do {
            // When
            _ = try storage.fetch(forKey: .init(name: "nonExistingFile"))
        } catch let error as KeychainStorage.Error {
            // Then
            if case let .other(inner) = error, let cocoa = inner as? CocoaError, cocoa.code == CocoaError.fileNoSuchFile {
                // ok
            } else {
                XCTFail("Unexpected error")
            }
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
        
        // Given
        mock.getError = nil

        do {
            // When
            _ = try storage.fetch(forKey: .init(name: "nonExistingFile"))
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
    }
    
    @KeychainActor
    func testMockedSave() async {
        // Given
        let mock = KeychainHelperMock(serviceName: "mock")
        let storage = KeychainStorage(keychain: mock)
        mock.setError = .status(.max)

        do {
            // When
            try storage.save(.init(), forKey: .init(name: "nonExistingFile"))
        } catch let error as KeychainStorage.Error {
            // Then
            if case .os(.max) = error {
                // ok
            } else {
                XCTFail("Unexpected error")
            }
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
        
        // Given
        mock.setError = nil

        do {
            // When
            try storage.save(.init(), forKey: .init(name: "nonExistingFile"))
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
    }
    
    @KeychainActor
    func testMockedDelete() async {
        // Given
        let mock = KeychainHelperMock(serviceName: "mock")
        let storage = KeychainStorage(keychain: mock)
        mock.removeError = .status(.max)

        do {
            // When
            try storage.delete(forKey: .init(name: "nonExistingFile"))
        } catch let error as KeychainStorage.Error {
            // Then
            if case .os(.max) = error {
                // ok
            } else {
                XCTFail("Unexpected error")
            }
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
        
        // Given
        mock.removeError = nil

        do {
            // When
            try storage.delete(forKey: .init(name: "nonExistingFile"))
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
    }
    
    @KeychainActor
    func testMockedSet() async {
        // Given
        let mock = KeychainHelperMock(serviceName: "mock")
        let storage = KeychainStorage(keychain: mock)
        mock.removeError = .status(.max)

        do {
            // When
            try storage.set(nil, forKey: .init(name: "nonExistingFile"))
        } catch let error as KeychainStorage.Error {
            // Then
            if case .os(.max) = error {
                // ok
            } else {
                XCTFail("Unexpected error")
            }
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
        
        // Given
        mock.removeError = nil

        do {
            // When
            try storage.set(nil, forKey: .init(name: "nonExistingFile"))
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
        
        // Given
        mock.setError = .status(.max)

        do {
            // When
            try storage.set(.init(), forKey: .init(name: "nonExistingFile"))
        } catch let error as KeychainStorage.Error {
            // Then
            if case .os(.max) = error {
                // ok
            } else {
                XCTFail("Unexpected error")
            }
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
        
        // When
        mock.setError = nil

        do {
            // When
            try storage.set(.init(), forKey: .init(name: "nonExistingFile"))
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
    }
    
    @KeychainActor
    func testMockedClear() async {
        // Given
        let mock = KeychainHelperMock(serviceName: "mock")
        let storage = KeychainStorage(keychain: mock)
        mock.removeAllError = .status(.max)

        do {
            // When
            try storage.clear()
        } catch let error as KeychainStorage.Error {
            // Then
            if case .os(.max) = error {
                // ok
            } else {
                XCTFail("Unexpected error")
            }
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
        
        // Given
        mock.removeAllError = nil

        do {
            // When
            try storage.clear()
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
    }
}
