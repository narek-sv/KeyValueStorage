//
//  SQLiteIntegrationTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import XCTest
import Foundation
import SQLite3
import KeyValueStorage // not @testable: real SQLite through the public API

/// The default backing store and locator against real SQLite, in a temporary folder of each test's own.
final class SQLiteIntegrationTests: XCTestCase {
    private let fileManager = FileManager.default
    private let scope = SQLiteStorage.Scope.own(namespace: "test")
    private var base: URL!
    private var locator: TestSQLiteLocator!
    /// `scope`'s database, in a folder made ahead.
    private var database: URL!

    override func setUpWithError() throws {
        let base = fileManager.temporaryDirectory.appendingPathComponent("SQLiteIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        self.base = base
        locator = TestSQLiteLocator(base: base)
        database = try locator.databaseURL(for: scope)
        try fileManager.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: base)
        }
    }

    // MARK: Files

    func testTheLocatorsLookupsReturnTheSystemsDirectories() {
        let locator = DefaultSQLiteLocator()

        XCTAssertEqual(locator.temporaryDirectory, fileManager.temporaryDirectory)
        XCTAssertEqual(locator.systemDirectory(.applicationSupportDirectory), fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        // Outside a sandbox, macOS returns a container for any group ID
        let groupId = "group.not.entitled.\(UUID().uuidString)"
        XCTAssertEqual(locator.groupDirectory(for: groupId), fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupId))
        XCTAssertEqual(locator.ownIdentifier, OwnIdentity.identifier)
    }

    func testTheDatabaseIsHiddenInTheNamespacesFolder() throws {
        // Given
        let storage = try storage(.own(namespace: "name"))

        // When
        try storage.save(Data([1]), forKey: "key")

        // Then
        let folder = try locator.databaseURL(for: .own(namespace: "name")).deletingLastPathComponent()
        XCTAssertEqual(folder.path, base.appendingPathComponent("support/app/name!/i").path)
        let files = try fileManager.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(files, [".KeyValueStorage.sqlite", ".KeyValueStorage.sqlite-shm", ".KeyValueStorage.sqlite-wal"])
    }

    func testEachProtectionIsADatabaseOfItsOwnInItsClass() throws {
        // `.none` opens, but can't be checked: macOS reports the default class for it
        _ = try storage(.own(protection: .none, namespace: "test"))
        let protections: [(SQLiteStorage.Protection, FileProtectionType)] = [
            (.whileLocked, .complete),
            (.whileLockedUnlessOpen, .completeUnlessOpen),
            (.untilFirstUnlock, .completeUntilFirstUserAuthentication)
        ]

        for (protection, expected) in protections {
            // When
            let scope = SQLiteStorage.Scope.own(protection: protection, namespace: "test")
            try storage(scope).save(Data([1]), forKey: "key")

            // Then: the scope's own database and its log
            let database = try locator.databaseURL(for: scope)
            XCTAssertNotEqual(database, self.database)
            let classes = try [database.path, database.path + "-wal"].map {
                try fileManager.attributesOfItem(atPath: $0)[.protectionKey] as? FileProtectionType
            }

            try XCTSkipIf(classes.contains(nil), "This volume doesn't report data protection")
            XCTAssertEqual(classes, [expected, expected])
        }
    }

    // MARK: Values

    func testValuesPersistAcrossInstances() throws {
        // Given
        var storage: SQLiteStorage? = try self.storage()
        try storage?.save(Data([1]), forKey: "key")

        // When
        storage = nil

        // Then
        XCTAssertEqual(try self.storage().fetch(forKey: "key"), Data([1]))
    }

    func testInstancesSharingADatabaseSeeEachOthersChanges() throws {
        // Given
        let first = try storage()
        let second = try storage()

        // When
        try first.save(Data([1]), forKey: "key")
        try second.save(Data([2]), forKey: "other")

        // Then
        XCTAssertEqual(try second.fetch(forKey: "key"), Data([1]))
        XCTAssertEqual(try first.fetch(forKey: "other"), Data([2]))

        // When
        try second.clear()

        // Then
        XCTAssertNil(try first.fetch(forKey: "key"))
        XCTAssertNil(try first.fetch(forKey: "other"))
    }

    func testValuesRoundTripExactly() throws {
        // Given
        let storage = try storage()
        let values = [Data(), Data((0...255).map { UInt8($0) }), Data((0..<1_048_576).map { UInt8(truncatingIfNeeded: $0 &* 31) })]

        for value in values {
            // When
            try storage.save(value, forKey: "key")

            // Then: an empty value is a value, not `nil`
            XCTAssertEqual(try storage.fetch(forKey: "key"), value)
        }
    }

    func testEveryKeyIsARowOfItsOwn() throws {
        // Given: keys that differ only in case, after a NUL, or in how `é` is written
        let storage = try storage()
        let keys: [SQLiteStorage.Key] = ["", ".", "..", "../escaped", "a/b", "a\0b", "a\0c", "Key", "key", "\u{E9}", "e\u{301}", "ключ 🔑", .init(String(repeating: "ж", count: 10_000))]

        // When
        for (index, key) in keys.enumerated() {
            try storage.save(Data([UInt8(index)]), forKey: key)
        }

        // Then
        for (index, key) in keys.enumerated() {
            XCTAssertEqual(try storage.fetch(forKey: key), Data([UInt8(index)]), key.string.debugDescription)
        }
    }

    // MARK: Concurrency

    func testOneInstanceIsSafeToShareBetweenThreads() throws {
        // Given
        let storage = try storage()
        let failures = Failures()

        // When: 200 threads save and fetch keys of their own at once
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            let key = SQLiteStorage.Key("key\(index)")
            do {
                try storage.save(Data([UInt8(index % 256)]), forKey: key)
                if try storage.fetch(forKey: key) != Data([UInt8(index % 256)]) {
                    failures.append("key\(index) read back another value")
                }
            } catch {
                failures.append("key\(index): \(error)")
            }
        }

        // Then
        XCTAssertEqual(failures.all, [])
    }

    // MARK: Errors

    func testAFileWhereTheFolderGoesIsReportedAndKept() throws {
        // Given
        let file = try locator.databaseURL(for: .own(namespace: "blocked")).deletingLastPathComponent()
        try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: file)

        // When
        let error = storageError { _ = try storage(.own(namespace: "blocked")) }

        // Then
        guard case .other? = error else {
            return XCTFail("Expected .other, got \(String(describing: error))")
        }

        XCTAssertEqual(try Data(contentsOf: file), Data([1]))
    }

    func testAFolderWhereTheDatabaseGoesIsReported() throws {
        // Given
        try fileManager.createDirectory(at: database, withIntermediateDirectories: true)

        // When - Then
        assertSQLiteError(storageError { _ = try storage() }, SQLITE_CANTOPEN)
    }

    func testACorruptDatabaseIsReportedAndKept() throws {
        // Given
        let corrupt = Data(repeating: 0x2A, count: 4096)
        try corrupt.write(to: database)

        // When - Then
        assertSQLiteError(storageError { _ = try storage() }, SQLITE_NOTADB)
        XCTAssertEqual(try Data(contentsOf: database), corrupt)
    }

    func testADatabaseWhoseTableIsAViewIsReported() throws {
        // Given: another app's schema, which reads like the storage's table but can't be written
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(database.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(connection, "CREATE VIEW KeyValueStorage AS SELECT 'key' AS key, x'00' AS value", nil, nil, nil), SQLITE_OK)
        sqlite3_close_v2(connection)

        // When - Then
        assertSQLiteError(storageError { _ = try storage() }, SQLITE_ERROR)
    }

    func testABusyDatabaseFailsAfterTheTimeoutWhileReadsGoOn() throws {
        // Given: another connection, like another process's, holds the write lock
        let storage = try storage()
        try storage.save(Data([1]), forKey: "key")
        let other = try openConnection()
        defer { sqlite3_close_v2(other) }
        XCTAssertEqual(sqlite3_exec(other, "BEGIN EXCLUSIVE", nil, nil, nil), SQLITE_OK)

        // When
        let start = Date()
        let error = storageError { try storage.save(Data([2]), forKey: "key") }

        // Then: the save waits for the 1 s busy timeout, and readers don't wait for the writer in WAL mode
        assertSQLiteError(error, SQLITE_BUSY)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.9)
        XCTAssertEqual(try storage.fetch(forKey: "key"), Data([1]))

        // When
        XCTAssertEqual(sqlite3_exec(other, "ROLLBACK", nil, nil, nil), SQLITE_OK)
        try storage.save(Data([2]), forKey: "key")

        // Then
        XCTAssertEqual(try storage.fetch(forKey: "key"), Data([2]))
    }

    func testADroppedTableFailsUntilTheDatabaseIsReopened() throws {
        // Given
        let storage = try storage()
        try storage.save(Data([1]), forKey: "key")
        let other = try openConnection()
        defer { sqlite3_close_v2(other) }
        XCTAssertEqual(sqlite3_exec(other, "DROP TABLE KeyValueStorage", nil, nil, nil), SQLITE_OK)

        // When - Then
        assertSQLiteError(storageError { _ = try storage.fetch(forKey: "key") }, SQLITE_ERROR)
        assertSQLiteError(storageError { try storage.save(Data([2]), forKey: "key") }, SQLITE_ERROR)
        assertSQLiteError(storageError { try storage.delete(forKey: "key") }, SQLITE_ERROR)
        assertSQLiteError(storageError { try storage.clear() }, SQLITE_ERROR)

        // When
        let reopened = try self.storage()
        try reopened.save(Data([2]), forKey: "key")

        // Then: opening creates the table again
        XCTAssertEqual(try reopened.fetch(forKey: "key"), Data([2]))
    }

    // MARK: Helpers

    private func storage(_ scope: SQLiteStorage.Scope? = nil) throws(SQLiteStorage.Error) -> SQLiteStorage {
        try SQLiteStorage(scope: scope ?? self.scope, backingStore: DefaultSQLiteBackingStoreWrapper(), locator: locator)
    }

    /// A second connection to the database, like another process would open.
    private func openConnection() throws -> OpaquePointer {
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(database.path, &connection, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        return try XCTUnwrap(connection)
    }

    /// The error `body` throws; without the `FullTypedThrows` feature, Swift infers closures as throwing `any Error`.
    private func storageError(file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) -> SQLiteStorage.Error? {
        do {
            try body()
            return nil
        } catch {
            guard let error = error as? SQLiteStorage.Error else {
                XCTFail("Expected an SQLiteStorage.Error, got \(error)", file: file, line: line)
                return nil
            }

            return error
        }
    }

    private func assertSQLiteError(_ error: SQLiteStorage.Error?, _ expected: Int32, file: StaticString = #filePath, line: UInt = #line) {
        guard case let .sqlite(code, message)? = error else {
            return XCTFail("Expected .sqlite, got \(String(describing: error))", file: file, line: line)
        }

        XCTAssertEqual(code, expected, message, file: file, line: line)
        XCTAssertFalse(message.isEmpty, file: file, line: line)
    }
}
