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
    
    func testKeychainIsConfigurable() {
        // Given: an existing Keychain Sharing group and a service that other code already saves items under
        let domain = KeychainStorage.Domain.appGroup(groupId: "TEAMID.group.shared", container: "existing.service")

        // When
        let storage = KeychainStorage(domain: domain)

        // Then
        XCTAssertEqual(storage.domain, domain)
    }

    func testDomainIsReadable() throws {
        // Given
        let container = UUID().uuidString
        addTeardownBlock {
            try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent(container, isDirectory: true))
        }

        let inMemoryDomain = InMemoryStorage.Domain.app(container: "publicAPIDomain")
        let userDefaultsDomain = UserDefaultsStorage.Domain.app(.suite(container: "publicAPIDomain"))
        let keychainDomain = KeychainStorage.Domain.appGroup(groupId: "group.shared", container: "publicAPIDomain")
        let fileDomain = FileStorage.Domain.app(.temporary(container: container))
        let sqliteDomain = SQLiteStorage.Domain.app(.temporary(container: container))
        let inMemory = InMemoryStorage(domain: inMemoryDomain)
        let userDefaults = try UserDefaultsStorage(domain: userDefaultsDomain)
        let keychain = KeychainStorage(domain: keychainDomain)
        let file = try FileStorage(domain: fileDomain)
        let sqlite = try SQLiteStorage(domain: sqliteDomain)

        // When - Then
        XCTAssertEqual(inMemory.domain, inMemoryDomain)
        XCTAssertEqual(userDefaults.domain, userDefaultsDomain)
        XCTAssertEqual(keychain.domain, keychainDomain)
        XCTAssertEqual(file.domain, fileDomain)
        XCTAssertEqual(sqlite.domain, sqliteDomain)
        if #available(watchOS 9.0, *) {
            let ubiquitousDomain = UbiquitousStorage.Domain.shared(container: "publicAPIDomain")
            XCTAssertEqual(UbiquitousStorage(domain: ubiquitousDomain, backingStorage: InMemoryUbiquitousStore()).domain, ubiquitousDomain)
        }
    }

    func testStoragesAcceptBackingStorages() throws {
        // Given: two default in-memory storages with the same domain, and one with a backing store of its own
        let container = "publicAPIBacking-\(UUID().uuidString)"
        let first = InMemoryStorage(domain: .app(container: container))
        let second = InMemoryStorage(domain: .app(container: container))
        let isolated = InMemoryStorage(domain: .app(container: container), backingStorage: IsolatedInMemoryStore())
        let keychain = KeychainStorage(domain: .default, backingStorage: InMemoryKeychain())

        // When
        first.save(Data([1]), forKey: "key")
        try keychain.save(Data([2]), forKey: .init(name: "key"))

        // Then: the default backing store is shared by the whole process
        XCTAssertEqual(second.fetch(forKey: "key"), Data([1]))
        XCTAssertNil(isolated.fetch(forKey: "key"))
        XCTAssertEqual(try keychain.fetch(forKey: .init(name: "key")), Data([2]))
        first.clear()
    }

    func testStoragesThatCantFailSetWithoutTry() throws {
        // Given
        let container = "publicAPISet-\(UUID().uuidString)"
        let inMemory = InMemoryStorage(domain: .app(container: container))
        let userDefaults = try UserDefaultsStorage(domain: .app(.suite(container: container)))
        defer { userDefaults.clear() }

        // When - Then: no `try`
        inMemory.set(Data([1]), forKey: "key")
        userDefaults.set(Data([2]), forKey: "key")
        XCTAssertEqual(inMemory.fetch(forKey: "key"), Data([1]))
        XCTAssertEqual(userDefaults.fetch(forKey: "key"), Data([2]))

        inMemory.set(nil, forKey: "key")
        userDefaults.set(nil, forKey: "key")
        XCTAssertNil(inMemory.fetch(forKey: "key"))
        XCTAssertNil(userDefaults.fetch(forKey: "key"))
    }

    func testDefaultInitializersUseTheDefaultDomain() throws {
        // No `try`: these storages can't fail to initialize
        XCTAssertEqual(InMemoryStorage().domain, .default)
        XCTAssertEqual(KeychainStorage().domain, .default)
        if #available(watchOS 9.0, *) {
            XCTAssertEqual(UbiquitousStorage().domain, .default)
        }

        XCTAssertEqual(try FileStorage().domain, .default)
        XCTAssertEqual(try UserDefaultsStorage().domain, .default)
    }
}

private final class CountingFactory: DefaultUnifiedStorageFactory, @unchecked Sendable {
    private(set) var dataStorageCalls = 0
    private(set) var codingStorageCalls = 0

    override func dataStorage<Storage: KeyValueDataStorage>(for domain: Storage.Domain) async throws -> Storage {
        dataStorageCalls += 1
        return try await super.dataStorage(for: domain)
    }

    override func codingStorage<Storage: KeyValueDataStorage>(for storage: Storage) async throws -> KeyValueCodingStorage<Storage> {
        codingStorageCalls += 1
        return try await super.codingStorage(for: storage)
    }
}
