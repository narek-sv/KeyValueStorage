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
        let defaultStorage = UnifiedStorage(factory: .default)
        let observableStorage = UnifiedStorage(factory: .default.observable())
        let entry = InMemoryStorage.Entry<Int>(key: "publicAPI")

        // When
        let defaultPublisher = try await defaultStorage.publisher(for: entry)
        let observablePublisher = try await observableStorage.publisher(for: entry)

        // Then
        XCTAssertNil(defaultPublisher)
        XCTAssertNotNil(observablePublisher)
    }

    /// A factory that only picks the coder: the default coding storage codes with it.
    func testAFactoryCanPickTheCoderAlone() async throws {
        // Given
        let namespace = ExactString("publicAPICoder-\(UUID().uuidString)")
        let storage = UnifiedStorage(factory: .default.coder(PropertyListDataCoder()))
        let entry = InMemoryStorage.Entry<String>(key: "key", scope: .own(namespace: namespace))
        
        // When
        try await storage.save("value", to: entry)
        let fetched = try await storage.fetch(entry)
        
        // Then: a binary property list, not the raw coder's UTF-8
        XCTAssertEqual(fetched, "value")
        let stored = InMemoryStorage(scope: .own(namespace: namespace)).fetch(forKey: "key")
        XCTAssertEqual(stored.map { Array($0.prefix(6)) }, Array("bplist".utf8))
    }
    
    /// An entry whose key is made at runtime takes the `String` as it is, and reaches the same value as the key written any other way.
    func testAnEntryWithAStringKeyReachesItsValue() async throws {
        // Given
        let namespace = ExactString("publicAPIStringKey-\(UUID().uuidString)")
        let storage = UnifiedStorage()
        let name = "user-\(42)"

        // When
        try await storage.save(1, to: InMemoryStorage.Entry<Int>(key: name, scope: .own(namespace: namespace)))
        let fetched = try await storage.fetch(InMemoryStorage.Entry<Int>(key: "user-42", scope: .own(namespace: namespace)))

        // Then
        XCTAssertEqual(fetched, 1)
        let coding = CodingStorage(storage: InMemoryStorage(scope: .own(namespace: namespace)), coder: JSONDataCoder())
        XCTAssertEqual(try coding.fetch(forKey: CodingStorageKey<InMemoryStorage, Int>(key: name)), 1)
    }

    /// Entries declared in an extension of `UnifiedStorage.Entry` are named after a dot, as the README suggests.
    func testAnEntryOfTheExtensionIsNamedAfterADot() async throws {
        // Given
        let storage = UnifiedStorage()
        try await storage.delete(.launches)

        // When
        try await storage.save(1, to: .launches)
        let updated = try await storage.update(.launches) { ($0 ?? 0) + 1 }
        let fetched = try await storage.fetch(.launches)

        // Then
        XCTAssertEqual(updated, 2)
        XCTAssertEqual(fetched, 2)
        try await storage.delete(.launches)
    }

    /// An app's own modifier implements only the steps it changes; the others are what the modifiers before it make.
    func testAModifierOfTheAppsOwnImplementsOnlyWhatItChanges() async throws {
        // Given
        let counter = CountingModifier()
        let storage = UnifiedStorage(factory: .default.observable().modifier(counter))

        // When
        let publisher = try await storage.publisher(for: InMemoryStorage.Entry<Int>(key: "publicAPI"))

        // Then: it counted the creation, and the storage is still observable
        XCTAssertEqual(counter.dataStorageCalls, 1)
        XCTAssertEqual(counter.codingStorageCalls, 1)
        XCTAssertNotNil(publisher)
    }

    /// A factory creates file storages with a locator of the app's own, and every other storage as before.
    func testAFactoryCreatesOneStorageTypeWithALocatorOfItsOwn() async throws {
        // Given
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("publicAPI-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: folder)
        }

        let storage = UnifiedStorage(factory: .default.dataStorage(for: FileStorage.self) { scope throws(FileStorage.Error) in
            try FileStorage(scope: scope, locator: FolderFileLocator(folder: folder))
        })
        let other = InMemoryStorage.Entry<Int>(key: "key", scope: .own(namespace: .init("publicAPILocator-\(UUID().uuidString)")))

        // When
        try await storage.save("value", to: FileStorage.Entry<String>(key: "key"))
        try await storage.save(1, to: other)
        let fetched = try await storage.fetch(FileStorage.Entry<String>(key: "key"))

        // Then: the file in the folder, and the other storage the default one
        XCTAssertEqual(fetched, "value")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["key"])
        XCTAssertNotNil(InMemoryStorage(scope: other.scope).fetch(forKey: "key"))
    }

    /// Modifiers for one storage type chain, each creating its type with a backing store of its own, and keep the ones for
    /// every type.
    func testModifiersForOneStorageTypeChainAndKeepTheOnesForEveryType() async throws {
        // Given: on an observable factory, in-memory and keychain storages with backing stores of their own
        let inMemoryStore = IsolatedInMemoryStore()
        let storage = UnifiedStorage(factory: .default
            .observable()
            .dataStorage(for: InMemoryStorage.self) { scope throws(InMemoryStorage.Error) in
                InMemoryStorage(scope: scope, backingStore: inMemoryStore)
            }
            .dataStorage(for: KeychainStorage.self) { scope throws(KeychainStorage.Error) in
                KeychainStorage(scope: scope, backingStore: InMemoryKeychain())
            })
        let entry = InMemoryStorage.Entry<Int>(key: "key", scope: .own(namespace: .init("publicAPIChain-\(UUID().uuidString)")))
        let token = KeychainStorage.Entry<String>(key: "token")

        // When
        let publisher = try await storage.publisher(for: entry)
        try await storage.save(1, to: entry)
        try await storage.save("secret", to: token)
        let fetchedToken = try await storage.fetch(token)

        // Then: still observable, and in the closures' backing stores, not the process-wide in-memory one or the keychain
        XCTAssertNotNil(publisher)
        XCTAssertNil(InMemoryStorage(scope: entry.scope).fetch(forKey: "key"))
        XCTAssertNotNil(InMemoryStorage(scope: entry.scope, backingStore: inMemoryStore).fetch(forKey: "key"))
        XCTAssertEqual(fetchedToken, "secret")
    }

    /// An app's own storage that needs more than its scope, such as a token, is created by `dataStorage(for:_:)`, which
    /// passes its error on as the storage's own.
    func testAFactoryCreatesAStorageThatNeedsMoreThanItsScope() async throws {
        // Given
        let entry = RemoteStorage.Entry<String>(key: "name", scope: .init(namespace: "publicAPI-\(UUID().uuidString)"))
        let signedIn = UnifiedStorage(factory: .default.dataStorage(for: RemoteStorage.self) { scope throws(URLError) in
            try await RemoteStorage(scope: scope, token: "token")
        })
        let signedOut = UnifiedStorage(factory: .default.dataStorage(for: RemoteStorage.self) { scope throws(URLError) in
            try await RemoteStorage(scope: scope, token: nil)
        })

        // When
        try await signedIn.save("Alice", to: entry)
        let fetched = try await signedIn.fetch(entry)

        // Then
        XCTAssertEqual(fetched, "Alice")
        do throws(CodingStorageError<RemoteStorage>) {
            _ = try await signedOut.fetch(entry)
            XCTFail("Expected the storage's own error")
        } catch {
            guard case let .storage(error) = error, error.code == .userAuthenticationRequired else {
                return XCTFail("Unexpected \(error)")
            }
        }
    }

    /// An `ObservableStorage` subclass of the app's own changes how values are saved, for one storage type through
    /// `observableStorage(for:_:)`, or for every type through a modifier of the app's own.
    func testAnObservableStorageSubclassOfTheAppsOwnObservesOneOrEveryStorageType() async throws {
        // Given
        let entry = InMemoryStorage.Entry<Int>(key: "key", scope: .own(namespace: .init("publicAPISubclass-\(UUID().uuidString)")))
        let oneType = UnifiedStorage(factory: .default.observableStorage(for: InMemoryStorage.self) { coding in
            DoublingObservableStorage(coding)
        })
        let everyType = UnifiedStorage(factory: .default.modifier(ObserveThroughDoubling()))

        // When
        try await oneType.save(1, to: entry)
        let first = try await oneType.fetch(entry)
        try await everyType.save(2, to: entry)
        let second = try await everyType.fetch(entry)

        // Then
        XCTAssertEqual(first, 2)
        XCTAssertEqual(second, 4)
        try await oneType.delete(entry)
    }

    /// An `AsyncCodingStorage` subclass of the app's own changes each operation, for a storage type through the factory's
    /// `codingStorage(for:_:)`.
    func testACodingStorageSubclassOfTheAppsOwnChangesEachOperation() async throws {
        // Given
        let calls = Calls()
        let storage = UnifiedStorage(factory: .default.codingStorage(for: InMemoryStorage.self) { storage, coder in
            RecordingCodingStorage(storage: storage, coder: coder, calls: calls)
        })
        let entry = InMemoryStorage.Entry<Int>(key: "key", scope: .own(namespace: .init("publicAPICoding-\(UUID().uuidString)")))

        // When
        try await storage.save(1, to: entry)
        let fetched = try await storage.fetch(entry)
        try await storage.set(2, to: entry)
        try await storage.delete(entry)
        try await storage.clear(storage: InMemoryStorage.self, forScope: entry.scope)

        // Then: each through the subclass, which then did what its superclass does
        XCTAssertEqual(calls.all, ["save", "fetch", "set", "delete", "clear"])
        XCTAssertEqual(fetched, 1)
    }

    /// A `CodingStorage` subclass of the app's own changes each operation.
    func testASynchronousCodingStorageSubclassOfTheAppsOwnChangesEachOperation() throws {
        // Given
        let calls = Calls()
        let storage = InMemoryStorage(scope: .own(namespace: .init("publicAPISyncCoding-\(UUID().uuidString)")))
        let coding = RecordingSynchronousCodingStorage(storage: storage, calls: calls)
        let key = CodingStorageKey<InMemoryStorage, Int>(key: "key")

        // When
        try coding.save(1, forKey: key)
        let fetched = try coding.fetch(forKey: key)
        try coding.set(2, forKey: key)
        try coding.delete(forKey: key)
        try coding.clear()

        // Then: each through the subclass, which then did what its superclass does
        XCTAssertEqual(calls.all, ["save", "fetch", "set", "delete", "clear"])
        XCTAssertEqual(fetched, 1)
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
        let scope = KeychainStorage.Scope.iCloud(.appGroup(id: "TEAMID.group.shared"), protection: .afterFirstUnlock, namespace: "auth")

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

    /// Each storage's full initializer defaults the backing store and the locator to the ones `init(scope:)` uses, so a
    /// client passes only the one it changes.
    func testAStorageTakesOnlyTheDependencyItChanges() throws {
        // Given: scopes of this test's own
        let name = ExactString("publicAPIDefaults-\(UUID().uuidString)")
        let fileScope = FileStorage.Scope.own(.temporary, namespace: name)
        let sqliteScope = SQLiteStorage.Scope.own(.temporary, namespace: name)
        // The namespace's folder, which File and SQLite share
        let folder = try DefaultSQLiteLocator().databaseURL(for: sqliteScope).deletingLastPathComponent().deletingLastPathComponent()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: folder)
        }

        // When - Then: each shares its values with the storage `init(scope:)` creates
        let inMemory = InMemoryStorage(scope: .own(namespace: name))
        try assertShareValues(inMemory, InMemoryStorage(scope: .own(namespace: name), backingStore: DefaultInMemoryBackingStoreWrapper()))
        try assertShareValues(inMemory, InMemoryStorage(scope: .own(namespace: name), locator: DefaultInMemoryLocator()))

        let file = try FileStorage(scope: fileScope)
        try assertShareValues(file, try FileStorage(scope: fileScope, backingStore: DefaultFileBackingStoreWrapper()))
        try assertShareValues(file, try FileStorage(scope: fileScope, locator: DefaultFileLocator()))

        let sqlite = try SQLiteStorage(scope: sqliteScope)
        try assertShareValues(sqlite, try SQLiteStorage(scope: sqliteScope, backingStore: DefaultSQLiteBackingStoreWrapper()))
        try assertShareValues(sqlite, try SQLiteStorage(scope: sqliteScope, locator: DefaultSQLiteLocator()))

        let userDefaults = try UserDefaultsStorage(scope: .own(namespace: name))
        try assertShareValues(userDefaults, try UserDefaultsStorage(scope: .own(namespace: name), backingStore: DefaultUserDefaultsBackingStoreWrapper()))
        try assertShareValues(userDefaults, try UserDefaultsStorage(scope: .own(namespace: name), locator: DefaultUserDefaultsLocator()))

        // The real keychain and iCloud store need entitlements that test bundles can't have: only the locators default here
        let keychainStore = InMemoryKeychain()
        try assertShareValues(KeychainStorage(scope: .own(namespace: name), backingStore: keychainStore),
                              KeychainStorage(scope: .own(namespace: name), backingStore: keychainStore, locator: DefaultKeychainLocator()))
        if #available(watchOS 9.0, *) {
            let ubiquitousStore = InMemoryUbiquitousStore()
            try assertShareValues(UbiquitousStorage(scope: .iCloud(.own, namespace: name), backingStore: ubiquitousStore),
                                  UbiquitousStorage(scope: .iCloud(.own, namespace: name), backingStore: ubiquitousStore, locator: DefaultUbiquitousLocator()))
        }
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
        let coding = CodingStorage(storage: storage)
        let key = CodingStorageKey<InMemoryStorage, String>(key: "name")

        // When
        storage.save(Data([1]), forKey: "raw")
        try coding.save("Alice", forKey: key)

        // Then
        XCTAssertEqual(storage.fetch(forKey: "raw"), Data([1]))
        XCTAssertEqual(try coding.fetch(forKey: key), "Alice")
        try coding.clear()
        XCTAssertNil(try coding.fetch(forKey: key))
    }

    /// An app's own asynchronous storage, such as a server-backed one, works through `UnifiedStorage` with entries of its own.
    func testAnAsyncStorageWorksThroughUnifiedStorage() async throws {
        // Given
        let storage = UnifiedStorage(factory: .default.observable())
        let entry = RemoteStorage.Entry<String>(key: "name", scope: .init(namespace: "publicAPI-\(UUID().uuidString)"))
        let publisher = try await storage.publisher(for: entry, includingCurrentValue: false)
        let published = expectation(description: "published")
        let subscription = publisher?.sink { value in
            if value == "Alice" {
                published.fulfill()
            }
        }

        // When
        try await storage.save("Alice", to: entry)
        let fetched = try await storage.fetch(entry)
        try await storage.delete(entry)
        let deleted = try await storage.fetch(entry)
        try await storage.save("Bob", to: entry)
        try await storage.clear(storage: RemoteStorage.self, forScope: entry.scope)
        let cleared = try await storage.fetch(entry)

        // Then
        XCTAssertEqual(fetched, "Alice")
        XCTAssertNil(deleted)
        XCTAssertNil(cleared)
        await fulfillment(of: [published], timeout: 5)
        subscription?.cancel()
    }

    /// The built-in storages are thread-safe, so `UnifiedStorage` shares a synchronous one between concurrent tasks safely.
    func testABuiltInSynchronousStorageIsSharedSafely() async throws {
        // Given
        let scope = SQLiteStorage.Scope.own(.temporary, namespace: .init("publicAPIIsolated-\(UUID().uuidString)"))
        let folder = try DefaultSQLiteLocator().databaseURL(for: scope).deletingLastPathComponent().deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = UnifiedStorage()

        // When: concurrent saves and fetches of 200 keys
        let values = try await withThrowingTaskGroup(of: (Int, Int?).self) { group in
            for index in 0..<200 {
                group.addTask {
                    let entry = SQLiteStorage.Entry<Int>(key: .init("key\(index)"), scope: scope)
                    try await storage.save(index, to: entry)
                    return (index, try await storage.fetch(entry))
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
    /// and one that isn't, through `IsolatedDataStorage`.
    func testCustomSynchronousStoragesWorkThroughUnifiedStorage() async throws {
        // Given
        let storage = UnifiedStorage()
        let shared = LockedStorage.Entry<String>(key: "name", scope: .init(namespace: "publicAPI-\(UUID().uuidString)"))
        let isolated = IsolatedDataStorage<PlainStorage>.Entry<String>(key: "name")

        // When
        try await storage.save("Alice", to: shared)
        try await storage.save("Bob", to: isolated)

        // Then
        let sharedValue = try await storage.fetch(shared)
        let isolatedValue = try await storage.fetch(isolated)
        XCTAssertEqual(sharedValue, "Alice")
        XCTAssertEqual(isolatedValue, "Bob")
    }

    /// A storage's own `set`, such as one request that writes or removes a value, is what every layer calls.
    func testAStoragesOwnSetIsWhatEveryLayerCalls() async throws {
        // Given
        let scope = NamespaceScope(namespace: "publicAPIOwnSet-\(UUID().uuidString)")
        let storage = UnifiedStorage(observable: true)
        let entry = OwnSetStorage.Entry<Int>(key: "count", scope: scope)
        let coding = CodingStorage(storage: OwnSetStorage(scope: scope))
        let isolated = IsolatedDataStorage(OwnSetStorage(scope: scope))

        // When: a set, an update and an unset through `UnifiedStorage`, and a set through a coding and an isolated storage
        try await storage.set(1, to: entry)
        let updated = try await storage.update(entry) { ($0 ?? 0) + 1 }
        try await storage.set(nil, to: entry)
        try coding.set(3, forKey: CodingStorageKey(key: "count"))
        await isolated.set(Data("4".utf8), forKey: "count")

        // Then: five writes, each through the storage's own `set`
        XCTAssertEqual(updated, 2)
        XCTAssertEqual(OwnSetStorage.sets(in: scope), 5)
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
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

    // MARK: Helpers

    /// A value `storage` saves, `other` fetches; then it's deleted.
    private func assertShareValues<Storage: DataStorage>(
        _ storage: Storage,
        _ other: Storage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws where Storage.Key == ExactString {
        try storage.save(Data([1]), forKey: "key")
        XCTAssertEqual(try other.fetch(forKey: "key"), Data([1]), "\(Storage.self)", file: file, line: line)
        try storage.delete(forKey: "key")
    }
}

/// As the README suggests, so the entries are named after a dot.
private extension UnifiedStorage.Entry {
    static var launches: InMemoryStorage.Entry<Int> {
        .init(key: "launches", scope: .own(namespace: "publicAPIStaticEntries"))
    }
}

/// Counts the storages and coding storages it creates, through the modifiers before it.
/// Unchecked: used from one test at a time.
private final class CountingModifier: UnifiedStorage.Factory.Modifier, @unchecked Sendable {
    private(set) var dataStorageCalls = 0
    private(set) var codingStorageCalls = 0

    func dataStorage<Storage: UnifiedStorable>(
        for scope: Storage.Scope,
        previous: () async throws(Storage.Error) -> Storage
    ) async throws(Storage.Error) -> Storage {
        dataStorageCalls += 1
        return try await previous()
    }

    func codingStorage<Storage: UnifiedStorable>(
        for storage: Storage,
        coder: any DataCoder,
        previous: () async -> AsyncCodingStorage<Storage>
    ) async -> AsyncCodingStorage<Storage> {
        codingStorageCalls += 1
        return await previous()
    }
}

/// Keeps every scope's files in one folder, which is enough for a test that uses one scope.
/// Unchecked: used from one test at a time.
private final class FolderFileLocator: DefaultFileLocator, @unchecked Sendable {
    private let folder: URL

    init(folder: URL) {
        self.folder = folder
    }

    override func directory(for scope: FileStorage.Scope) throws(FileStorage.Error) -> URL {
        folder
    }
}

/// Saves `Int` values doubled, as a subclass that changes how values are saved would.
private final class DoublingObservableStorage<Storage: UnifiedStorable>: ObservableStorage<Storage>, @unchecked Sendable {
    override func save<Value: CodingValue>(_ value: Value, forKey key: CodingStorageKey<Storage, Value>) async throws(Error) {
        if let number = value as? Int, let doubled = number * 2 as? Value {
            return try await super.save(doubled, forKey: key)
        }

        try await super.save(value, forKey: key)
    }
}

/// Records each operation, then does what `AsyncCodingStorage` does.
private final class RecordingCodingStorage<Storage: AsyncDataStorage>: AsyncCodingStorage<Storage>, @unchecked Sendable {
    private let calls: Calls

    init(storage: Storage, coder: any DataCoder, calls: Calls) {
        self.calls = calls
        super.init(storage: storage, coder: coder)
    }

    override func fetch<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>) async throws(Error) -> Value? {
        calls.append("fetch")
        return try await super.fetch(forKey: key)
    }

    override func save<Value: CodingValue>(_ value: Value, forKey key: CodingStorageKey<Storage, Value>) async throws(Error) {
        calls.append("save")
        try await super.save(value, forKey: key)
    }

    override func set<Value: CodingValue>(_ value: Value?, forKey key: CodingStorageKey<Storage, Value>) async throws(Error) {
        calls.append("set")
        try await super.set(value, forKey: key)
    }

    override func delete<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>) async throws(Error) {
        calls.append("delete")
        try await super.delete(forKey: key)
    }

    override func clear() async throws(Error) {
        calls.append("clear")
        try await super.clear()
    }
}

/// Records each operation, then does what `CodingStorage` does.
private final class RecordingSynchronousCodingStorage<Storage: DataStorage>: CodingStorage<Storage>, @unchecked Sendable {
    private let calls: Calls

    init(storage: Storage, calls: Calls) {
        self.calls = calls
        super.init(storage: storage)
    }

    override func fetch<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>) throws(Error) -> Value? {
        calls.append("fetch")
        return try super.fetch(forKey: key)
    }

    override func save<Value: CodingValue>(_ value: Value, forKey key: CodingStorageKey<Storage, Value>) throws(Error) {
        calls.append("save")
        try super.save(value, forKey: key)
    }

    override func set<Value: CodingValue>(_ value: Value?, forKey key: CodingStorageKey<Storage, Value>) throws(Error) {
        calls.append("set")
        try super.set(value, forKey: key)
    }

    override func delete<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>) throws(Error) {
        calls.append("delete")
        try super.delete(forKey: key)
    }

    override func clear() throws(Error) {
        calls.append("clear")
        try super.clear()
    }
}

/// The operations a recording coding storage was called for, in order.
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = [String]()

    var all: [String] {
        lock.withLock { calls }
    }

    func append(_ call: String) {
        lock.withLock { calls.append(call) }
    }
}

/// Observes every storage type through `DoublingObservableStorage`.
private struct ObserveThroughDoubling: UnifiedStorage.Factory.Modifier {
    func observableStorage<Storage: UnifiedStorable>(
        for coding: AsyncCodingStorage<Storage>,
        previous: () async -> ObservableStorage<Storage>?
    ) async -> ObservableStorage<Storage>? {
        DoublingObservableStorage(coding)
    }
}

// MARK: - RemoteStorage

/// An app's own asynchronous storage, as a server-backed one would be.
private actor RemoteStorage: AsyncDataStorage {
    typealias Key = String
    typealias Error = URLError

    struct Scope: DataStorageScope {
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

    /// As one that signs in to its server would: it can't without a token.
    init(scope: Scope, token: String?) async throws(URLError) {
        guard token != nil else {
            throw URLError(.userAuthenticationRequired)
        }

        self.scope = scope
    }

    func fetch(forKey key: String) async throws(URLError) -> Data? {
        values[key]
    }

    func save(_ value: Data, forKey key: String) async throws(URLError) {
        values[key] = value
    }

    func set(_ value: Data?, forKey key: String) async throws(URLError) {
        values[key] = value
    }

    func delete(forKey key: String) async throws(URLError) {
        values[key] = nil
    }

    func clear() async throws(URLError) {
        values = [:]
    }
}

// MARK: - Custom Storages

private struct NamespaceScope: DataStorageScope {
    let namespace: String

    static var `default`: Self {
        .init(namespace: "default")
    }
}

/// An app's own synchronous storage that isn't thread-safe.
private final class PlainStorage: DataStorage {
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
private final class LockedStorage: DataStorage, @unchecked Sendable {
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

/// A storage with a `set` of its own, as one that writes or removes a value in one request would have; counts its calls by
/// namespace, since `UnifiedStorage` creates an instance of its own.
private final class OwnSetStorage: DataStorage, @unchecked Sendable {
    typealias Key = String
    typealias Error = Never

    private static let lock = NSLock()
    nonisolated(unsafe) private static var setCalls = [String: Int]()

    let scope: NamespaceScope
    private let lock = NSLock()
    private var values = [String: Data]()

    init(scope: NamespaceScope) {
        self.scope = scope
    }

    /// How many times the storages of `scope` were set.
    static func sets(in scope: NamespaceScope) -> Int {
        lock.withLock { setCalls[scope.namespace, default: 0] }
    }

    func fetch(forKey key: String) -> Data? { lock.withLock { values[key] } }
    func save(_ value: Data, forKey key: String) { lock.withLock { values[key] = value } }
    func delete(forKey key: String) { _ = lock.withLock { values.removeValue(forKey: key) } }
    func clear() { lock.withLock { values = [:] } }

    func set(_ value: Data?, forKey key: String) {
        Self.lock.withLock { Self.setCalls[scope.namespace, default: 0] += 1 }
        lock.withLock { values[key] = value }
    }
}
