//
//  DefaultSQLiteLocatorTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class DefaultSQLiteLocatorTests: XCTestCase {
    private let locator = FixedDirectoriesSQLiteLocator()

    // MARK: Database

    func testAppScopesUseTheirBaseDirectory() throws {
        let custom = URL(fileURLWithPath: "/custom", isDirectory: true)
        let bases: [(SQLiteStorage.AppScope, String)] = [
            (.applicationSupport, "/support"),
            (.cache, "/caches"),
            (.documents, "/documents"),
            (.temporary, "/temporary"),
            (.directory(at: custom), "/custom")
        ]

        for (appScope, path) in bases {
            XCTAssertEqual(try databasePath(.app(appScope)), path + "/.KeyValueStorage.sqlite")
            XCTAssertEqual(try databasePath(.app(appScope, namespace: .directory(named: "name"))), path + "/name!/.KeyValueStorage.sqlite")
        }
    }

    func testAppGroupScopesUseTheGroupContainer() throws {
        XCTAssertEqual(try databasePath(.appGroup(groupId: "group.test")), "/group/.KeyValueStorage.sqlite")
        XCTAssertEqual(try databasePath(.appGroup(groupId: "group.test", namespace: .directory(named: "name"))), "/group/name!/.KeyValueStorage.sqlite")
    }

    func testDefaultScopeUsesTheLibrarysFolderInApplicationSupport() throws {
        XCTAssertEqual(try databasePath(.default), "/support/!key!value!storage!/.KeyValueStorage.sqlite")
    }

    func testProtectionDoesntChangeTheDatabase() throws {
        XCTAssertEqual(try databasePath(.app(.temporary, protection: .complete)), try databasePath(.app(.temporary)))
    }

    func testMissingBaseDirectoriesThrowTheirDirectory() {
        locator.directories = [:]

        assertThrows(SQLiteStorage.Error.directoryNotFound(.applicationSupportDirectory)) {
            try databasePath(.app(.applicationSupport))
        }

        assertThrows(SQLiteStorage.Error.directoryNotFound(.cachesDirectory)) {
            try databasePath(.app(.cache))
        }

        assertThrows(SQLiteStorage.Error.directoryNotFound(.documentDirectory)) {
            try databasePath(.app(.documents))
        }
    }

    func testMissingGroupContainerThrowsTheGroupId() {
        assertThrows(SQLiteStorage.Error.groupDirectoryNotFound("group.other")) {
            try databasePath(.appGroup(groupId: "group.other"))
        }
    }

    func testDirectoryMustBeAFileURL() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/folder"))
        assertThrows(SQLiteStorage.Error.invalidDirectory(url)) {
            try databasePath(.app(.directory(at: url)))
        }
    }

    // MARK: Namespaces

    func testNamespacesShareTheFileStoragesFolder() throws {
        let base = URL(fileURLWithPath: "/base", isDirectory: true)
        let names = (0..<128).map { String(UnicodeScalar(UInt8($0))) } + ["", "KeyValueStorage", "a/b", "\u{E9}", "e\u{301}", "🙂"]

        for name in names {
            let database = try locator.databaseURL(for: .app(.directory(at: base), namespace: .directory(named: name)))
            let folder = try DefaultFileLocator().directory(for: .app(.directory(at: base), namespace: .directory(named: name)))
            XCTAssertEqual(database.deletingLastPathComponent().path, folder.path, name.debugDescription)
        }
    }

    func testNamespacesLongerThanAFolderNameThrow() throws {
        XCTAssertNoThrow(try databasePath(.app(.temporary, namespace: .directory(named: String(repeating: "a", count: 254)))))

        let name = String(repeating: "a", count: 255)
        assertThrows(SQLiteStorage.Error.invalidNamespace(name)) {
            try databasePath(.app(.temporary, namespace: .directory(named: name)))
        }
    }

    func testNamespaceIsCheckedBeforeTheEnvironment() {
        let name = String(repeating: "A", count: 128)
        assertThrows(SQLiteStorage.Error.invalidNamespace(name)) {
            try databasePath(.appGroup(groupId: "group.other", namespace: .directory(named: name)))
        }
    }

    // MARK: Keys

    func testKeysAreStoredAsTheyAre() {
        for key in ["", "key", "Key", "a/b", "a\0b", "\u{E9}", "e\u{301}", "🙂"] {
            XCTAssertTrue(locator.storedKey(forKey: key, in: .default).unicodeScalars.elementsEqual(key.unicodeScalars), key.debugDescription)
        }
    }

    // MARK: Helpers

    private func databasePath(_ scope: SQLiteStorage.Scope) throws(SQLiteStorage.Error) -> String {
        try locator.databaseURL(for: scope).path
    }
}
