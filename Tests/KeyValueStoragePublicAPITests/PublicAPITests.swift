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
    
    @KeychainActor
    func testKeychainIsConfigurable() {
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
