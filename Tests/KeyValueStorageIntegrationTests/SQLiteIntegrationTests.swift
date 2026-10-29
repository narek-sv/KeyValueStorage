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
    private var base: URL!

    private var scope: SQLiteStorage.Scope {
        .app(.directory(at: base))
    }

    private var database: URL {
        base.appendingPathComponent(".KeyValueStorage.sqlite", isDirectory: false)
    }

    override func setUpWithError() throws {
        let base = fileManager.temporaryDirectory.appendingPathComponent("SQLiteIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        self.base = base
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
    }

    func testTheDatabaseIsHiddenInTheNamespacesFolder() throws {
        // Given
        let storage = try SQLiteStorage(scope: .app(.directory(at: base), namespace: .directory(named: "name")))

        // When
        try storage.save(Data([1]), forKey: "key")

        // Then
        let files = try fileManager.contentsOfDirectory(atPath: base.appendingPathComponent("name!").path).sorted()
        XCTAssertEqual(files, [".KeyValueStorage.sqlite", ".KeyValueStorage.sqlite-shm", ".KeyValueStorage.sqlite-wal"])
    }

    func testEachOpenAppliesTheScopesProtection() throws {
        // `.none` opens, but can't be checked: macOS reports the default class for it
        _ = try SQLiteStorage(scope: .app(.directory(at: base), protection: .none))
        let protections: [(SQLiteStorage.Protection, FileProtectionType)] = [
            (.complete, .complete),
            (.completeUnlessOpen, .completeUnlessOpen),
            (.completeUntilFirstUserAuthentication, .completeUntilFirstUserAuthentication)
        ]

        for (protection, expected) in protections {
            // When
            let storage = try SQLiteStorage(scope: .app(.directory(at: base), protection: protection))
            try storage.save(Data([1]), forKey: "key")

            // Then: the database and its log
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
        var storage: SQLiteStorage? = try SQLiteStorage(scope: scope)
        try storage?.save(Data([1]), forKey: "key")

        // When
        storage = nil

        // Then
        XCTAssertEqual(try SQLiteStorage(scope: scope).fetch(forKey: "key"), Data([1]))
    }

    func testInstancesSharingADatabaseSeeEachOthersChanges() throws {
        // Given
        let first = try SQLiteStorage(scope: scope)
        let second = try SQLiteStorage(scope: scope)

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
        let storage = try SQLiteStorage(scope: scope)
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
        let storage = try SQLiteStorage(scope: scope)
        let keys = ["", ".", "..", "../escaped", "a/b", "a\0b", "a\0c", "Key", "key", "\u{E9}", "e\u{301}", "ключ 🔑", String(repeating: "ж", count: 10_000)]

        // When
        for (index, key) in keys.enumerated() {
            try storage.save(Data([UInt8(index)]), forKey: key)
        }

        // Then
        for (index, key) in keys.enumerated() {
            XCTAssertEqual(try storage.fetch(forKey: key), Data([UInt8(index)]), key.debugDescription)
        }
    }

    // MARK: Errors

    func testAFileWhereTheFolderGoesIsReportedAndKept() throws {
        // Given
        let file = base.appendingPathComponent("blocked!", isDirectory: false)
        try Data([1]).write(to: file)

        // When
        let error = storageError { _ = try SQLiteStorage(scope: .app(.directory(at: base), namespace: .directory(named: "blocked"))) }

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
        assertSQLiteError(storageError { _ = try SQLiteStorage(scope: scope) }, SQLITE_CANTOPEN)
    }

    func testACorruptDatabaseIsReportedAndKept() throws {
        // Given
        let corrupt = Data(repeating: 0x2A, count: 4096)
        try corrupt.write(to: database)

        // When - Then
        assertSQLiteError(storageError { _ = try SQLiteStorage(scope: scope) }, SQLITE_NOTADB)
        XCTAssertEqual(try Data(contentsOf: database), corrupt)
    }

    func testADatabaseWhoseTableIsAViewIsReported() throws {
        // Given: another app's schema, which reads like the storage's table but can't be written
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(database.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(connection, "CREATE VIEW KeyValueStorage AS SELECT 'key' AS key, x'00' AS value", nil, nil, nil), SQLITE_OK)
        sqlite3_close_v2(connection)

        // When - Then
        assertSQLiteError(storageError { _ = try SQLiteStorage(scope: scope) }, SQLITE_ERROR)
    }

    func testABusyDatabaseFailsAfterTheTimeoutWhileReadsGoOn() throws {
        // Given: another connection, like another process's, holds the write lock
        let storage = try SQLiteStorage(scope: scope)
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
        let storage = try SQLiteStorage(scope: scope)
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
        let reopened = try SQLiteStorage(scope: scope)
        try reopened.save(Data([2]), forKey: "key")

        // Then: opening creates the table again
        XCTAssertEqual(try reopened.fetch(forKey: "key"), Data([2]))
    }

    // MARK: Helpers

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
