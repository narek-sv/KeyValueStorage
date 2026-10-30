//
//  SQLiteStorageTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import XCTest
import Foundation
import SQLite3
@testable import KeyValueStorage

/// The storage's rules against a mock database; the real one is in `SQLiteIntegrationTests`.
final class SQLiteStorageTests: XCTestCase {
    private let backingStore = SQLiteBackingStoreMock()
    private let locator = SQLiteLocatorStub()
    private let scope = SQLiteStorage.Scope.own(.temporary, namespace: "name")
    private let data = Data([0xAA, 0xBB])

    // MARK: Initializers

    func testInitOpensTheLocatorsDatabaseInAFolderItCreates() throws {
        // When
        _ = try makeStorage()

        // Then
        XCTAssertEqual(locator.calls, [.databaseURL(scope)])
        XCTAssertEqual(backingStore.calls, [
            .createDirectory(URL(fileURLWithPath: "/located", isDirectory: true)),
            .open(locator.databaseURL, nil)
        ])
    }

    func testInitThrowsTheLocatorsErrorBeforeTheFileSystem() {
        // Given
        locator.databaseURLError = .invalidNamespace("name")

        // When - Then
        assertThrows(SQLiteStorage.Error.invalidNamespace("name")) { try makeStorage() }
        XCTAssertEqual(backingStore.calls, [])
    }

    func testInitReportsAFolderThatCantBeCreatedWithoutOpening() {
        // Given
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError)
        backingStore.createDirectoryError = error

        // When - Then
        assertThrows(SQLiteStorage.Error.other(error)) { try makeStorage() }
        XCTAssertEqual(backingStore.calls, [.createDirectory(URL(fileURLWithPath: "/located", isDirectory: true))])
    }

    func testInitReportsOpenErrors() {
        // Given
        backingStore.openError = SQLiteError(code: SQLITE_NOTADB, message: "file is not a database")

        // When - Then
        assertThrows(SQLiteStorage.Error.sqlite(code: SQLITE_NOTADB, message: "file is not a database")) { try makeStorage() }
    }

    func testEachProtectionReachesOpen() throws {
        let protections: [(SQLiteStorage.Protection, FileProtectionType?)] = [
            (.inherited, nil),
            (.none, FileProtectionType.none),
            (.untilFirstUnlock, .completeUntilFirstUserAuthentication),
            (.whileLocked, .complete),
            (.whileLockedUnlessOpen, .completeUnlessOpen)
        ]

        for (protection, expected) in protections {
            for scope in [SQLiteStorage.Scope.own(protection: protection, namespace: "name"), .appGroup(id: "group.test", protection: protection, namespace: "name")] {
                // When
                let backingStore = SQLiteBackingStoreMock()
                _ = try SQLiteStorage(scope: scope, backingStore: backingStore, locator: locator)

                // Then
                XCTAssertEqual(backingStore.calls.last, .open(locator.databaseURL, expected), "\(scope)")
            }
        }
    }

    func testScopeIsTheOneGiven() throws {
        XCTAssertEqual(try makeStorage().scope, scope)
    }

    // MARK: Operations

    func testOperationsUseExactlyTheLocatorsStoredKeys() throws {
        // Given
        let storage = try makeStorage()

        // When
        try storage.save(data, forKey: "key")
        let fetched = try storage.fetch(forKey: "key")
        try storage.delete(forKey: "key")
        let deleted = try storage.fetch(forKey: "key")
        try storage.clear()

        // Then
        XCTAssertEqual(fetched, data)
        XCTAssertNil(deleted)
        XCTAssertEqual(backingStore.database.calls, [
            .write(data, "located-key"), .read("located-key"), .remove("located-key"), .read("located-key"), .removeAll
        ])
        XCTAssertEqual(locator.calls.dropFirst(), Array(repeating: .storedKey("key", scope), count: 4)[...])
    }

    func testSetSavesAValueAndDeletesNil() throws {
        // Given
        let storage = try makeStorage()

        // When
        try storage.set(data, forKey: "key")
        try storage.set(nil, forKey: "key")

        // Then
        XCTAssertEqual(backingStore.database.calls, [.write(data, "located-key"), .remove("located-key")])
    }

    func testDatabaseErrorsAreReported() throws {
        // Given
        let storage = try makeStorage()
        backingStore.database.error = SQLiteError(code: SQLITE_BUSY, message: "database is locked")
        let expected = SQLiteStorage.Error.sqlite(code: SQLITE_BUSY, message: "database is locked")

        // When - Then
        assertThrows(expected) { try storage.fetch(forKey: "key") }
        assertThrows(expected) { try storage.save(data, forKey: "key") }
        assertThrows(expected) { try storage.delete(forKey: "key") }
        assertThrows(expected) { try storage.clear() }
    }

    // MARK: Helpers

    private func makeStorage() throws(SQLiteStorage.Error) -> SQLiteStorage {
        try SQLiteStorage(scope: scope, backingStore: backingStore, locator: locator)
    }
}
