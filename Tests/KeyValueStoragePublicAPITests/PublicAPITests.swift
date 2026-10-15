//
//  PublicAPITests.swift
//
//
//  Created by Narek Sahakyan on 15.10.26.
//

import XCTest
import Foundation
import KeyValueStorage // intentionally not @testable: verifies what clients can actually access

final class PublicAPITests: XCTestCase {
    func testFactoriesAreConstructible() async throws {
        // Given
        let defaultStorage = UnifiedStorage(factory: DefaultUnifiedStorageFactory())
        let observableStorage = UnifiedStorage(factory: ObservableUnifiedStorageFactory())
        let key = InMemoryKey<Int>(key: "publicAPI")

        // When
        let defaultPublisher = try await defaultStorage.publisher(forKey: key)
        let observablePublisher = try await observableStorage.publisher(forKey: key)

        // Then
        XCTAssertNil(defaultPublisher)
        XCTAssertNotNil(observablePublisher)
    }

    func testFactoriesAcceptACoder() async throws {
        // Given
        let storage = UnifiedStorage(factory: ObservableUnifiedStorageFactory(coder: PropertyListDataCoder()))
        let key = InMemoryKey<String>(key: "publicAPICoder")
        
        // When
        try await storage.save("value", forKey: key)
        let fetched = try await storage.fetch(forKey: key)
        let publisher = try await storage.publisher(forKey: key)
        
        // Then
        XCTAssertEqual(fetched, "value")
        XCTAssertNotNil(publisher)
        _ = UnifiedStorage(factory: DefaultUnifiedStorageFactory(coder: JSONDataCoder()))
    }
    
    func testDefaultFactoryIsSubclassable() async throws {
        // Given
        let factory = CountingFactory()
        let storage = UnifiedStorage(factory: factory)

        // When
        _ = try await storage.fetch(forKey: InMemoryKey<Int>(key: "publicAPI"))

        // Then
        XCTAssertEqual(factory.dataStorageCalls, 1)
        XCTAssertEqual(factory.codingStorageCalls, 1)
    }
    
    func testRawDataCoderIsConfigurable() async throws {
        // Given
        let coder = RawDataCoder(fallback: PropertyListDataCoder())
        
        // When
        let string = try await coder.encode("token")
        let int = try await coder.encode(42)
        let expectedInt = try PropertyListDataCoder().encode(42)
        
        // Then
        XCTAssertEqual(string, Data("token".utf8))
        XCTAssertEqual(int, expectedInt)
    }
    
    @KeychainActor
    func testKeychainIsConfigurable() async {
        // Given
        let keychain = KeychainWrapperSpy(serviceName: "existing.service", accessGroup: "TEAMID.group.shared")
        let domain = KeychainStorage.Domain(groupId: "group.shared", teamId: "TEAMID", service: "existing.service")
        
        // When
        let storage = KeychainStorage(keychain: keychain)
        _ = try? storage.fetch(forKey: .init(name: "token"))
        
        // Then
        XCTAssertEqual(keychain.fetchedKeys, ["token"])
        XCTAssertEqual(domain.service, keychain.serviceName)
        XCTAssertEqual(domain.accessGroup, keychain.accessGroup)
    }
    
    func testDomainIsReadableOutsideTheStorageActor() async throws {
        // Given
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        
        let keychainDomain = KeychainStorage.Domain(accessGroup: "group.shared")
        let inMemory = await InMemoryStorage(domain: "publicAPIDomain")
        let userDefaults = try await UserDefaultsStorage(domain: "publicAPIDomain")
        let keychain = await KeychainStorage(domain: keychainDomain)
        let file = await FileStorage(fileManager: .default, root: root)
        let sqlite = try await SQLiteStorage(fileManager: .default, root: root)
        
        // When - Then: read without await, like KeyValueCodingStorage does
        XCTAssertEqual(inMemory.domain, "publicAPIDomain")
        XCTAssertEqual(userDefaults.domain, "publicAPIDomain")
        XCTAssertEqual(keychain.domain, keychainDomain)
        XCTAssertNil(file.domain)
        XCTAssertNil(sqlite.domain)
    }
}

private final class KeychainWrapperSpy: KeychainWrapper, @unchecked Sendable {
    private(set) var fetchedKeys = [String]()
    
    override func get(forKey key: String, isSynchronizable: Bool = false) throws -> Data? {
        fetchedKeys.append(key)
        return nil
    }
}

private final class CountingFactory: DefaultUnifiedStorageFactory, @unchecked Sendable {
    private(set) var dataStorageCalls = 0
    private(set) var codingStorageCalls = 0

    override func dataStorage<Storage: KeyValueDataStorage>(for domain: Storage.Domain?) async throws -> Storage {
        dataStorageCalls += 1
        return try await super.dataStorage(for: domain)
    }

    override func codingStorage<Storage: KeyValueDataStorage>(for storage: Storage) async throws -> KeyValueCodingStorage<Storage> {
        codingStorageCalls += 1
        return try await super.codingStorage(for: storage)
    }
}
