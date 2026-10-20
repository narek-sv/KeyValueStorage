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
        let scope = KeychainStorage.Scope.appGroup(groupId: "TEAMID.group.shared", container: "existing.service")

        // When
        let storage = KeychainStorage(scope: scope)

        // Then
        XCTAssertEqual(storage.scope, scope)
    }

    func testScopeIsReadable() throws {
        // Given
        let container = UUID().uuidString
        addTeardownBlock {
            try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent(container, isDirectory: true))
        }

        let inMemoryScope = InMemoryStorage.Scope.app(container: "publicAPIScope")
        let userDefaultsScope = UserDefaultsStorage.Scope.app(.suite(container: "publicAPIScope"))
        let keychainScope = KeychainStorage.Scope.appGroup(groupId: "group.shared", container: "publicAPIScope")
        let fileScope = FileStorage.Scope.app(.temporary(container: container))
        let sqliteScope = SQLiteStorage.Scope.app(.temporary(container: container))
        let inMemory = InMemoryStorage(scope: inMemoryScope)
        let userDefaults = try UserDefaultsStorage(scope: userDefaultsScope)
        let keychain = KeychainStorage(scope: keychainScope)
        let file = try FileStorage(scope: fileScope)
        let sqlite = try SQLiteStorage(scope: sqliteScope)

        // When - Then
        XCTAssertEqual(inMemory.scope, inMemoryScope)
        XCTAssertEqual(userDefaults.scope, userDefaultsScope)
        XCTAssertEqual(keychain.scope, keychainScope)
        XCTAssertEqual(file.scope, fileScope)
        XCTAssertEqual(sqlite.scope, sqliteScope)
        if #available(watchOS 9.0, *) {
            let ubiquitousScope = UbiquitousStorage.Scope.shared(container: "publicAPIScope")
            XCTAssertEqual(UbiquitousStorage(scope: ubiquitousScope, backingStorage: InMemoryUbiquitousStore()).scope, ubiquitousScope)
        }
    }

    func testStoragesAcceptBackingStorages() throws {
        // Given: two default in-memory storages with the same scope, and one with a backing store of its own
        let container = "publicAPIBacking-\(UUID().uuidString)"
        let first = InMemoryStorage(scope: .app(container: container))
        let second = InMemoryStorage(scope: .app(container: container))
        let isolated = InMemoryStorage(scope: .app(container: container), backingStorage: IsolatedInMemoryStore())
        let keychain = KeychainStorage(scope: .default, backingStorage: InMemoryKeychain())

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
        let inMemory = InMemoryStorage(scope: .app(container: container))
        let userDefaults = try UserDefaultsStorage(scope: .app(.suite(container: container)))
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

    func testDefaultInitializersUseTheDefaultScope() throws {
        // No `try`: these storages can't fail to initialize
        XCTAssertEqual(InMemoryStorage().scope, .default)
        XCTAssertEqual(KeychainStorage().scope, .default)
        if #available(watchOS 9.0, *) {
            XCTAssertEqual(UbiquitousStorage().scope, .default)
        }

        XCTAssertEqual(try FileStorage().scope, .default)
        XCTAssertEqual(try UserDefaultsStorage().scope, .default)
    }
}

private final class CountingFactory: DefaultUnifiedStorageFactory, @unchecked Sendable {
    private(set) var dataStorageCalls = 0
    private(set) var codingStorageCalls = 0

    override func dataStorage<Storage: KeyValueDataStorage>(for scope: Storage.Scope) async throws -> Storage {
        dataStorageCalls += 1
        return try await super.dataStorage(for: scope)
    }

    override func codingStorage<Storage: KeyValueDataStorage>(for storage: Storage) async throws -> KeyValueCodingStorage<Storage> {
        codingStorageCalls += 1
        return try await super.codingStorage(for: storage)
    }
}
