//
//  PublicAPITests.swift
//  KeyValueStorage
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
        let scope = KeychainStorage.Scope.appGroup(groupId: "TEAMID.group.shared", namespace: .service(named: "existing.service"))

        // When
        let storage = KeychainStorage(scope: scope)

        // Then
        XCTAssertEqual(storage.scope, scope)
    }

    func testScopeIsReadable() throws {
        // Given
        let directory = UUID().uuidString
        // The SQLite storage below makes its namespace's folder; the file storage writes nothing
        let folder = try DefaultSQLiteLocator().databaseURL(for: .own(.temporary, namespace: .init(directory))).deletingLastPathComponent().deletingLastPathComponent()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: folder)
        }

        let inMemoryScope = InMemoryStorage.Scope.app(namespace: .bucket(named: "publicAPIScope"))
        let userDefaultsScope = UserDefaultsStorage.Scope.app(.suite(named: "publicAPIScope"))
        let keychainScope = KeychainStorage.Scope.appGroup(groupId: "group.shared", namespace: .service(named: "publicAPIScope"))
        let fileScope = FileStorage.Scope.own(.temporary, namespace: .init(directory))
        let sqliteScope = SQLiteStorage.Scope.own(.temporary, namespace: .init(directory))
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
            let ubiquitousScope = UbiquitousStorage.Scope.shared(namespace: .keyPrefix(named: "publicAPIScope"))
            XCTAssertEqual(UbiquitousStorage(scope: ubiquitousScope, backingStore: InMemoryUbiquitousStore(), locator: DefaultUbiquitousLocator()).scope, ubiquitousScope)
        }
    }

    func testStoragesAcceptBackingStores() throws {
        // Given: two default in-memory storages with the same scope, and one with a backing store of its own
        let bucket = "publicAPIBacking-\(UUID().uuidString)"
        let first = InMemoryStorage(scope: .app(namespace: .bucket(named: bucket)))
        let second = InMemoryStorage(scope: .app(namespace: .bucket(named: bucket)))
        let isolated = InMemoryStorage(scope: .app(namespace: .bucket(named: bucket)), backingStore: IsolatedInMemoryStore(), locator: DefaultInMemoryLocator())
        let keychain = KeychainStorage(scope: .default, backingStore: InMemoryKeychain(), locator: DefaultKeychainLocator())

        // When
        first.save(Data([1]), forKey: "key")
        try keychain.save(Data([2]), forKey: .init(name: "key"))

        // Then: the default backing store is shared by the whole process
        XCTAssertEqual(second.fetch(forKey: "key"), Data([1]))
        XCTAssertNil(isolated.fetch(forKey: "key"))
        XCTAssertEqual(try keychain.fetch(forKey: .init(name: "key")), Data([2]))
        first.clear()
    }

    func testOperationsThatCantFailNeedNoTry() throws {
        // Given
        let name = "publicAPISet-\(UUID().uuidString)"
        let inMemory = InMemoryStorage(scope: .app(namespace: .bucket(named: name)))
        let userDefaults = try UserDefaultsStorage(scope: .app(.suite(named: name)))
        defer { userDefaults.clear() }

        // When - Then: no `try`, except for UserDefaults' saves, which throw `.keyOccupied`
        inMemory.set(Data([1]), forKey: "key")
        try userDefaults.set(Data([2]), forKey: "key")
        XCTAssertEqual(inMemory.fetch(forKey: "key"), Data([1]))
        XCTAssertEqual(userDefaults.fetch(forKey: "key"), Data([2]))

        inMemory.set(nil, forKey: "key")
        userDefaults.delete(forKey: "key")
        XCTAssertNil(inMemory.fetch(forKey: "key"))
        XCTAssertNil(userDefaults.fetch(forKey: "key"))
    }

    /// Compiles only while the storage and its locator throw `FileStorage.Error`, and clients can match every case.
    func testFileStorageThrowsItsOwnErrors() {
        let key = FileStorage.Key(String(repeating: "a", count: 256))
        do throws(FileStorage.Error) {
            let storage = try FileStorage(scope: .own(.temporary, namespace: "publicAPI-\(UUID().uuidString)"))
            _ = try storage.fetch(forKey: key)
            XCTFail("Expected .invalidKey")
        } catch {
            switch error {
            case .invalidKey(key):
                break
            case .invalidKey, .invalidNamespace, .pathOccupied, .directoryNotFound, .groupDirectoryNotFound, .protectedDataUnavailable, .other:
                XCTFail("Unexpected \(error)")
            }
        }

        do throws(FileStorage.Error) {
            _ = try DefaultFileLocator().fileName(forKey: key, in: .default)
            XCTFail("Expected .invalidKey")
        } catch {
            guard case .invalidKey(key) = error else {
                return XCTFail("Unexpected \(error)")
            }
        }
    }

    func testFileStorageAcceptsALocator() throws {
        // Given: a locator that keeps values in a folder of the app's choice, under a legacy prefix,
        // as an app adopting existing files might
        final class LegacyLocator: DefaultFileLocator {
            let folder: URL

            init(folder: URL) {
                self.folder = folder
            }

            override func directory(for scope: FileStorage.Scope) throws(FileStorage.Error) -> URL {
                folder
            }

            override func fileName(forKey key: FileStorage.Key, in scope: FileStorage.Scope) throws(FileStorage.Error) -> String {
                try "legacy-" + super.fileName(forKey: key, in: scope)
            }

            override func key(forFileName fileName: String, in scope: FileStorage.Scope) -> FileStorage.Key? {
                guard fileName.hasPrefix("legacy-") else {
                    return nil
                }

                return super.key(forFileName: String(fileName.dropFirst("legacy-".count)), in: scope)
            }
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("publicAPI-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: folder)
        }

        let storage = try FileStorage(scope: .default, backingStore: DefaultFileBackingStoreWrapper(), locator: LegacyLocator(folder: folder))

        // When
        try storage.save(Data([1]), forKey: "key")

        // Then
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["legacy-key"])
        try storage.clear()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
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

    override func dataStorage<Storage: KeyValueDataStorage>(for scope: Storage.Scope) async throws(Storage.Error) -> Storage {
        dataStorageCalls += 1
        return try await super.dataStorage(for: scope)
    }

    override func codingStorage<Storage: KeyValueDataStorage>(for storage: Storage) async -> KeyValueCodingStorage<Storage> {
        codingStorageCalls += 1
        return await super.codingStorage(for: storage)
    }
}
