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

    /// A factory that only picks the coder: the default `codingStorage(for:)` uses it.
    func testAFactoryCanPickTheCoderAlone() async throws {
        // Given
        let namespace = ExactString("publicAPICoder-\(UUID().uuidString)")
        let storage = UnifiedStorage(factory: PropertyListFactory())
        let key = InMemoryKey<String>(key: "key", scope: .own(namespace: namespace))
        
        // When
        try await storage.save("value", forKey: key)
        let fetched = try await storage.fetch(forKey: key)
        
        // Then: a binary property list, not the raw coder's UTF-8
        XCTAssertEqual(fetched, "value")
        let stored = InMemoryStorage(scope: .own(namespace: namespace)).fetch(forKey: "key")
        XCTAssertEqual(stored.map { Array($0.prefix(6)) }, Array("bplist".utf8))
    }
    
    func testAFactoryImplementsOnlyWhatItChanges() async throws {
        // Given
        let factory = CountingFactory()
        let storage = UnifiedStorage(factory: factory)

        // When
        _ = try await storage.fetch(forKey: InMemoryKey<Int>(key: "publicAPI"))

        // Then
        XCTAssertEqual(factory.dataStorageCalls, 1)
        XCTAssertEqual(factory.codingStorageCalls, 1)
    }
    
    func testRawDataCoderIsConfigurable() throws {
        // Given
        let coder = RawDataCoder(fallback: PropertyListDataCoder())
        
        // When
        let string = try coder.encode("token")
        let int = try coder.encode(42)
        let expectedInt = try PropertyListDataCoder().encode(42)
        
        // Then
        XCTAssertEqual(string, Data("token".utf8))
        XCTAssertEqual(int, expectedInt)
    }
    
    func testKeychainIsConfigurable() {
        // Given: synced items of a Keychain Sharing group, usable while locked
        let scope = KeychainStorage.Scope.iCloud(.appGroup(id: "TEAMID.group.shared"), protection: .untilFirstUnlock, namespace: "auth")

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

        let inMemoryScope = InMemoryStorage.Scope.own(namespace: "publicAPIScope")
        let userDefaultsScope = UserDefaultsStorage.Scope.own(namespace: "publicAPIScope")
        let keychainScope = KeychainStorage.Scope.appGroup(id: "group.shared", namespace: "publicAPIScope")
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
            let ubiquitousScope = UbiquitousStorage.Scope.iCloud(.own, namespace: "publicAPIScope")
            XCTAssertEqual(UbiquitousStorage(scope: ubiquitousScope, backingStore: InMemoryUbiquitousStore(), locator: DefaultUbiquitousLocator()).scope, ubiquitousScope)
        }
    }

    func testStoragesAcceptBackingStores() throws {
        // Given: two default in-memory storages with the same scope, and one with a backing store of its own
        let bucket = "publicAPIBacking-\(UUID().uuidString)"
        let first = InMemoryStorage(scope: .own(namespace: .init(bucket)))
        let second = InMemoryStorage(scope: .own(namespace: .init(bucket)))
        let isolated = InMemoryStorage(scope: .own(namespace: .init(bucket)), backingStore: IsolatedInMemoryStore(), locator: DefaultInMemoryLocator())
        let keychain = KeychainStorage(scope: .default, backingStore: InMemoryKeychain(), locator: DefaultKeychainLocator())

        // When
        first.save(Data([1]), forKey: "key")
        try keychain.save(Data([2]), forKey: "key")

        // Then: the default backing store is shared by the whole process
        XCTAssertEqual(second.fetch(forKey: "key"), Data([1]))
        XCTAssertNil(isolated.fetch(forKey: "key"))
        XCTAssertEqual(try keychain.fetch(forKey: "key"), Data([2]))
        first.clear()
    }

    func testOperationsThatCantFailNeedNoTry() throws {
        // Given
        let name = "publicAPISet-\(UUID().uuidString)"
        let inMemory = InMemoryStorage(scope: .own(namespace: .init(name)))
        let userDefaults = try UserDefaultsStorage(scope: .own(namespace: .init(name)))
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

    /// Compiles only while synchronous storages and the synchronous coding storage need no `await`, also inside `async` code.
    func testSynchronousStoragesNeedNoAwaitInAsyncCode() async throws {
        // Given
        let storage = InMemoryStorage(scope: .own(namespace: .init("publicAPISync-\(UUID().uuidString)")))
        let coding = KeyValueCodingStorage(storage: storage)
        let key = KeyValueCodingStorageKey<InMemoryStorage, String>(key: "name")

        // When
        storage.save(Data([1]), forKey: "raw")
        try coding.save("Alice", forKey: key)

        // Then
        XCTAssertEqual(storage.fetch(forKey: "raw"), Data([1]))
        XCTAssertEqual(try coding.fetch(forKey: key), "Alice")
        try coding.clear()
        XCTAssertNil(try coding.fetch(forKey: key))
    }

    /// An app's own asynchronous storage, such as a server-backed one, works through `UnifiedStorage` with a key of its own.
    func testAnAsyncStorageWorksThroughUnifiedStorage() async throws {
        // Given
        let storage = UnifiedStorage(factory: ObservableUnifiedStorageFactory())
        let key = RemoteKey<String>(key: "name", scope: .init(namespace: "publicAPI-\(UUID().uuidString)"))
        let publisher = try await storage.publisher(forKey: key, includingCurrentValue: false)
        let published = expectation(description: "published")
        let subscription = publisher?.sink { value in
            if value == "Alice" {
                published.fulfill()
            }
        }

        // When
        try await storage.save("Alice", forKey: key)
        let fetched = try await storage.fetch(forKey: key)
        try await storage.delete(forKey: key)
        let deleted = try await storage.fetch(forKey: key)
        try await storage.save("Bob", forKey: key)
        try await storage.clear(storage: RemoteStorage.self, forScope: key.scope)
        let cleared = try await storage.fetch(forKey: key)

        // Then
        XCTAssertEqual(fetched, "Alice")
        XCTAssertNil(deleted)
        XCTAssertNil(cleared)
        await fulfillment(of: [published], timeout: 5)
        subscription?.cancel()
    }

    /// The built-in keys isolate their storages, so `UnifiedStorage` shares a synchronous one between concurrent tasks safely.
    func testBuiltInKeysShareASynchronousStorageSafely() async throws {
        // Given
        let scope = SQLiteStorage.Scope.own(.temporary, namespace: .init("publicAPIIsolated-\(UUID().uuidString)"))
        let folder = try DefaultSQLiteLocator().databaseURL(for: scope).deletingLastPathComponent().deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = UnifiedStorage()

        // When: concurrent saves and fetches of 200 keys
        let values = try await withThrowingTaskGroup(of: (Int, Int?).self) { group in
            for index in 0..<200 {
                group.addTask {
                    let key = SQLiteKey<Int>(key: .init("key\(index)"), scope: scope)
                    try await storage.save(index, forKey: key)
                    return (index, try await storage.fetch(forKey: key))
                }
            }

            return try await group.reduce(into: [Int: Int?]()) { $0[$1.0] = $1.1 }
        }

        // Then
        XCTAssertEqual(values.count, 200)
        for (index, value) in values {
            XCTAssertEqual(value, index)
        }

        try await storage.clear(storage: SQLiteStorage.self, forScope: scope)
    }

    /// Compiles only while the built-in storages are `Sendable`: an instance can be shared between tasks.
    func testBuiltInStoragesAreSendable() async {
        // Given
        let storage = InMemoryStorage(scope: .own(namespace: .init("publicAPISendable-\(UUID().uuidString)")))

        // When: used from another task while this one keeps it
        await Task.detached { storage.save(Data([1]), forKey: "key") }.value
        let fetched = storage.fetch(forKey: "key")

        // Then
        XCTAssertEqual(fetched, Data([1]))
        _ = { (storage: FileStorage, sqlite: SQLiteStorage, keychain: KeychainStorage, defaults: UserDefaultsStorage) in
            Task.detached { _ = (storage, sqlite, keychain, defaults) }
        }
    }

    /// A custom synchronous storage that's `Sendable` works through `UnifiedStorage` as it is,
    /// and one that isn't, through `IsolatedKeyValueDataStorage`.
    func testCustomSynchronousStoragesWorkThroughUnifiedStorage() async throws {
        // Given
        let storage = UnifiedStorage()
        let shared = UnifiedStorageKey<LockedStorage, String>(key: "name", scope: .init(namespace: "publicAPI-\(UUID().uuidString)"))
        let isolated = UnifiedStorageKey<IsolatedKeyValueDataStorage<PlainStorage>, String>(key: "name")

        // When
        try await storage.save("Alice", forKey: shared)
        try await storage.save("Bob", forKey: isolated)

        // Then
        let sharedValue = try await storage.fetch(forKey: shared)
        let isolatedValue = try await storage.fetch(forKey: isolated)
        XCTAssertEqual(sharedValue, "Alice")
        XCTAssertEqual(isolatedValue, "Bob")
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
        /// Unchecked: used from one test at a time.
        final class LegacyLocator: DefaultFileLocator, @unchecked Sendable {
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

/// Counts its calls, and otherwise creates what the defaults do.
private final class CountingFactory: UnifiedStorageFactory, @unchecked Sendable {
    private(set) var dataStorageCalls = 0
    private(set) var codingStorageCalls = 0

    func dataStorage<Storage: AsyncKeyValueDataStorage & Sendable>(for scope: Storage.Scope) async throws(Storage.Error) -> Storage {
        dataStorageCalls += 1
        return try await Storage(scope: scope)
    }

    func codingStorage<Storage: AsyncKeyValueDataStorage & Sendable>(for storage: Storage) async -> AsyncKeyValueCodingStorage<Storage> {
        codingStorageCalls += 1
        return AsyncKeyValueCodingStorage(storage: storage, coder: coder(for: storage))
    }
}

/// Picks the coder and nothing else.
private struct PropertyListFactory: UnifiedStorageFactory {
    func coder<Storage: AsyncKeyValueDataStorage & Sendable>(for storage: Storage) -> any DataCoder {
        PropertyListDataCoder()
    }
}

// MARK: - RemoteStorage

/// An app's own asynchronous storage, as a server-backed one would be.
private actor RemoteStorage: AsyncKeyValueDataStorage {
    typealias Key = String
    typealias Error = URLError

    struct Scope: KeyValueDataStorageScope {
        let namespace: String

        static var `default`: Self {
            .init(namespace: "default")
        }
    }

    nonisolated let scope: Scope
    private var values = [String: Data]()

    init(scope: Scope) async throws(URLError) {
        self.scope = scope
    }

    func fetch(forKey key: String) async throws(URLError) -> Data? {
        values[key]
    }

    func save(_ value: Data, forKey key: String) async throws(URLError) {
        values[key] = value
    }

    func delete(forKey key: String) async throws(URLError) {
        values[key] = nil
    }

    func clear() async throws(URLError) {
        values = [:]
    }
}

private typealias RemoteKey<Value: CodingValue> = UnifiedStorageKey<RemoteStorage, Value>

// MARK: - Custom Storages

private struct NamespaceScope: KeyValueDataStorageScope {
    let namespace: String

    static var `default`: Self {
        .init(namespace: "default")
    }
}

/// An app's own synchronous storage that isn't thread-safe.
private final class PlainStorage: KeyValueDataStorage {
    typealias Key = String
    typealias Error = Never

    let scope: NamespaceScope
    private var values = [String: Data]()

    init(scope: NamespaceScope) {
        self.scope = scope
    }

    func fetch(forKey key: String) -> Data? { values[key] }
    func save(_ value: Data, forKey key: String) { values[key] = value }
    func delete(forKey key: String) { values[key] = nil }
    func clear() { values = [:] }
}

/// An app's own synchronous storage that is thread-safe, so `Sendable`.
private final class LockedStorage: KeyValueDataStorage, @unchecked Sendable {
    typealias Key = String
    typealias Error = Never

    let scope: NamespaceScope
    private let lock = NSLock()
    private var values = [String: Data]()

    init(scope: NamespaceScope) {
        self.scope = scope
    }

    func fetch(forKey key: String) -> Data? { lock.withLock { values[key] } }
    func save(_ value: Data, forKey key: String) { lock.withLock { values[key] = value } }
    func delete(forKey key: String) { _ = lock.withLock { values.removeValue(forKey: key) } }
    func clear() { lock.withLock { values = [:] } }
}
