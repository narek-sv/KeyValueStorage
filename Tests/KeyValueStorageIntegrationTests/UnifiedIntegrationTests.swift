//
//  UnifiedIntegrationTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

import XCTest
import Foundation
import KeyValueStorage // not @testable: the real storages through the public API

/// Every operation through `UnifiedStorage`, end to end, on each real storage: File and SQLite in a temporary folder of
/// each test's own, UserDefaults in the own suite of a test bundle ID, emptied after each test, and InMemory.
/// Keychain runs in KeychainHost; Ubiquitous needs a signed host.
final class UnifiedIntegrationTests: XCTestCase {
    private static let suiteBundleIdentifier = "UnifiedIntegrationTests"

    private var factory: TestStorageFactory!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("UnifiedIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        factory = TestStorageFactory(base: base, suiteBundleIdentifier: Self.suiteBundleIdentifier)
        let suiteName = try TestUserDefaultsLocator(bundleIdentifier: Self.suiteBundleIdentifier).suiteName(for: .own(namespace: "ns"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: base)
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
    }

    // MARK: Round Trips

    func testFileRoundTrips() async throws {
        try await assertRoundTrips(FileStorage.self, scopes: [.own(namespace: "ns"), .own(namespace: ""), .own(.cache, protection: .none, namespace: "ns"), .appGroup(id: "group", namespace: "ns")])
    }

    func testSQLiteRoundTrips() async throws {
        try await assertRoundTrips(SQLiteStorage.self, scopes: [.own(namespace: "ns"), .own(namespace: ""), .own(.temporary, protection: .none, namespace: "ns"), .appGroup(id: "group", namespace: "ns")])
    }

    func testUserDefaultsRoundTrips() async throws {
        try await assertRoundTrips(UserDefaultsStorage.self, scopes: [.own(namespace: "ns"), .own(namespace: ""), .own(namespace: "ns/\0")])
    }

    func testInMemoryRoundTrips() async throws {
        let namespace = "UnifiedIntegrationTests-\(UUID().uuidString)"
        try await assertRoundTrips(InMemoryStorage.self, scopes: [.own(namespace: .init(namespace)), .own(namespace: .init(namespace + "\0")), .own(namespace: .init(namespace + "/"))])
    }

    // MARK: Moves

    func testAMoveCarriesTheValueToANewProtectionOrNamespace() async throws {
        // Given: values saved before their entries' scopes changed
        let storage = UnifiedStorage(factory: factory)
        let file = FileStorage.Entry<String>(key: "avatar", scope: .own(protection: .afterFirstUnlock, namespace: "ns"))
        let sqlite = SQLiteStorage.Entry<String>(key: "record", scope: .own(namespace: "moved"))
        let defaults = UserDefaultsStorage.Entry<String>(key: "flag", scope: .own(namespace: "moved"))
        try await storage.save("file", to: FileStorage.Entry<String>(key: "avatar", scope: .own(namespace: "ns")))
        try await storage.save("sqlite", to: SQLiteStorage.Entry<String>(key: "record", scope: .own(namespace: "ns")))
        try await storage.save("defaults", to: UserDefaultsStorage.Entry<String>(key: "flag", scope: .own(namespace: "ns")))

        // When
        try await storage.move(file, from: .own(namespace: "ns"))
        try await storage.move(sqlite, from: .own(namespace: "ns"))
        try await storage.move(defaults, from: .own(namespace: "ns"))

        // Then: each value is in its entry's new scope only
        let movedFile = try await storage.fetch(file)
        let movedRecord = try await storage.fetch(sqlite)
        let movedFlag = try await storage.fetch(defaults)
        XCTAssertEqual(movedFile, "file")
        XCTAssertEqual(movedRecord, "sqlite")
        XCTAssertEqual(movedFlag, "defaults")
        let oldFile = try await storage.fetch(FileStorage.Entry<String>(key: "avatar", scope: .own(namespace: "ns")))
        let oldRecord = try await storage.fetch(SQLiteStorage.Entry<String>(key: "record", scope: .own(namespace: "ns")))
        let oldFlag = try await storage.fetch(UserDefaultsStorage.Entry<String>(key: "flag", scope: .own(namespace: "ns")))
        XCTAssertNil(oldFile)
        XCTAssertNil(oldRecord)
        XCTAssertNil(oldFlag)
    }

    // MARK: Closing

    func testAClosedDatabaseCanBeDeletedAndTheNextCallsStartANewOne() async throws {
        // Given: a SQLite scope with a value, its database open
        let storage = UnifiedStorage(factory: factory)
        let entry = SQLiteStorage.Entry<Int>(key: "key", scope: .own(namespace: "closed"))
        try await storage.save(1, to: entry)
        let database = try factory.sqliteLocator.databaseURL(for: entry.scope)

        // When: closed, then its files deleted, as for a damaged database; not awaited by the test, so a close or a call
        // that waits forever fails at the timeout instead of hanging
        let finished = expectation(description: "the close and the calls after it finished")
        let calls = Task {
            defer { finished.fulfill() }
            await storage.close(storage: SQLiteStorage.self, forScope: entry.scope)
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: database.path + suffix)
            }

            let fetched = try await storage.fetch(entry)
            try await storage.save(2, to: entry)
            return fetched
        }

        guard await XCTWaiter.fulfillment(of: [finished], timeout: 5) == .completed else {
            return XCTFail("The close or a call after it waited forever")
        }

        // Then: the next calls opened a new database, which another connection sees; the closed connection would have kept
        // the deleted file and its value
        let fetched = try await calls.value
        XCTAssertNil(fetched)
        let other = try SQLiteStorage(scope: entry.scope, backingStore: DefaultSQLiteBackingStoreWrapper(), locator: factory.sqliteLocator)
        XCTAssertEqual(try other.fetch(forKey: "key"), Data("2".utf8))
    }

    // MARK: Values

    func testEveryValueTypeKeepsItsBytesThroughEachStorage() async throws {
        // Given
        let storage = UnifiedStorage(factory: factory)
        let data = Data((0...255).map(UInt8.init))

        // When
        try await storage.save(data, to: FileStorage.Entry<Data>(key: "data", scope: .own(namespace: "ns")))
        try await storage.save(data, to: SQLiteStorage.Entry<Data>(key: "data", scope: .own(namespace: "ns")))
        try await storage.save(data, to: UserDefaultsStorage.Entry<Data>(key: "data", scope: .own(namespace: "ns")))
        try await storage.save("ключ 🔑", to: FileStorage.Entry<String>(key: "string", scope: .own(namespace: "ns")))

        // Then: raw bytes, as the default coder stores them
        let file = try FileStorage(scope: .own(namespace: "ns"), backingStore: DefaultFileBackingStoreWrapper(), locator: factory.fileLocator)
        XCTAssertEqual(try file.fetch(forKey: "data"), data)
        XCTAssertEqual(try file.fetch(forKey: "string"), Data("ключ 🔑".utf8))
        let fetchedSQLite = try await storage.fetch(SQLiteStorage.Entry<Data>(key: "data", scope: .own(namespace: "ns")))
        let fetchedUserDefaults = try await storage.fetch(UserDefaultsStorage.Entry<Data>(key: "data", scope: .own(namespace: "ns")))
        XCTAssertEqual(fetchedSQLite, data)
        XCTAssertEqual(fetchedUserDefaults, data)
    }

    // MARK: Helpers

    /// Each operation for keys and values with edge cases, in every scope; then `clear()` of one scope keeps the others.
    private func assertRoundTrips<Storage: UnifiedStorable>(
        _: Storage.Type,
        scopes: [Storage.Scope],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws where Storage.Key == ExactString {
        let storage = UnifiedStorage(factory: factory)
        let keys: [ExactString] = ["", "key", "Key", "a/b", "a\0b", "\u{E9}", "e\u{301}", "ключ 🔑", "%2F"]

        for (index, scope) in scopes.enumerated() {
            for key in keys {
                let string = Storage.Entry<String>(key: key, scope: scope)
                let number = Storage.Entry<Int>(key: .init("\(key)-int"), scope: scope)
                let value = "\(index):\(key)"

                let initial = try await storage.fetch(string)
                XCTAssertNil(initial, "\(scope) \(key)", file: file, line: line)
                try await storage.save(value, to: string)
                try await storage.set(index, to: number)
                let saved = try await storage.fetch(string)
                let savedNumber = try await storage.fetch(number)
                XCTAssertEqual(saved, value, "\(scope) \(key)", file: file, line: line)
                XCTAssertEqual(savedNumber, index, "\(scope) \(key)", file: file, line: line)
            }

            // Delete and set `nil` remove only their own key
            try await storage.delete(Storage.Entry<String>(key: "key", scope: scope))
            try await storage.set(nil, to: Storage.Entry<Int>(key: "key-int", scope: scope))
            let deleted = try await storage.fetch(Storage.Entry<String>(key: "key", scope: scope))
            let unset = try await storage.fetch(Storage.Entry<Int>(key: "key-int", scope: scope))
            let kept = try await storage.fetch(Storage.Entry<String>(key: "Key", scope: scope))
            XCTAssertNil(deleted, "\(scope)", file: file, line: line)
            XCTAssertNil(unset, "\(scope)", file: file, line: line)
            XCTAssertEqual(kept, "\(index):Key", "\(scope)", file: file, line: line)
        }

        // Every scope kept its own values, and clearing the first keeps the others'
        try await storage.clear(storage: Storage.self, forScope: scopes[0])
        for (index, scope) in scopes.enumerated() {
            for key in keys where key != "key" {
                let fetched = try await storage.fetch(Storage.Entry<String>(key: key, scope: scope))
                XCTAssertEqual(fetched, index == 0 ? nil : "\(index):\(key)", "\(scope) \(key)", file: file, line: line)
            }

            try await storage.clear(storage: Storage.self, forScope: scope)
        }
    }
}

// MARK: - TestStorageFactory

/// File, SQLite and UserDefaults at the test's places; every other storage as the default factory makes it.
private struct TestStorageFactory: UnifiedStorageFactory {
    let fileLocator: TestFileLocator
    let sqliteLocator: TestSQLiteLocator
    let userDefaultsLocator: TestUserDefaultsLocator

    init(base: URL, suiteBundleIdentifier: String) {
        fileLocator = TestFileLocator(base: base)
        sqliteLocator = TestSQLiteLocator(base: base)
        userDefaultsLocator = TestUserDefaultsLocator(bundleIdentifier: suiteBundleIdentifier)
    }

    func dataStorage<Storage: UnifiedStorable>(for scope: Storage.Scope) async throws(Storage.Error) -> Storage {
        if let scope = scope as? FileStorage.Scope, let made: Storage = try made({
            try FileStorage(scope: scope, backingStore: DefaultFileBackingStoreWrapper(), locator: fileLocator)
        }) {
            return made
        }

        if let scope = scope as? SQLiteStorage.Scope, let made: Storage = try made({
            try SQLiteStorage(scope: scope, backingStore: DefaultSQLiteBackingStoreWrapper(), locator: sqliteLocator)
        }) {
            return made
        }

        if let scope = scope as? UserDefaultsStorage.Scope, let made: Storage = try made({
            try UserDefaultsStorage(scope: scope, backingStore: DefaultUserDefaultsBackingStoreWrapper(), locator: userDefaultsLocator)
        }) {
            return made
        }

        return try await Storage(scope: scope)
    }

    /// The storage `body` makes, if it's a `Storage`; its error, which is then `Storage.Error`, is thrown as is.
    private func made<Storage: UnifiedStorable>(_ body: () throws -> any Sendable) throws(Storage.Error) -> Storage? {
        do {
            return try body() as? Storage
        } catch let error as Storage.Error {
            throw error
        } catch {
            return nil
        }
    }
}
