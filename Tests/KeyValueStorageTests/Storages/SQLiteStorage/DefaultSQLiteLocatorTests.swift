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

    func testOwnScopesUseTheirRetentionsBaseAndTheAppsFolder() throws {
        let bases: [(SQLiteStorage.Retention, String)] = [(.persistent, "/support"), (.cache, "/caches"), (.temporary, "/temporary")]
        for (retention, path) in bases {
            XCTAssertEqual(try databasePath(.own(retention, namespace: "name")), path + "/com%2etest%2e!app/name!/i/.KeyValueStorage.sqlite")
        }
    }

    func testAppGroupScopesUseTheGroupContainer() throws {
        XCTAssertEqual(try databasePath(.appGroup(id: "group.test", namespace: "name")), "/group/name!/i/.KeyValueStorage.sqlite")
    }

    func testEachProtectionIsADatabaseOfItsOwn() throws {
        let folders: [(SQLiteStorage.Protection, String)] = [(.inherited, "i"), (.none, "n"), (.untilFirstUnlock, "u"), (.whileLocked, "w"), (.whileLockedUnlessOpen, "o")]
        for (protection, folder) in folders {
            XCTAssertEqual(try databasePath(.own(protection: protection, namespace: "name")), "/support/com%2etest%2e!app/name!/\(folder)/.KeyValueStorage.sqlite")
            XCTAssertEqual(try databasePath(.appGroup(id: "group.test", protection: protection, namespace: "name")), "/group/name!/\(folder)/.KeyValueStorage.sqlite")
        }
    }

    func testDefaultScopeUsesTheLibrarysNamespaceInApplicationSupport() throws {
        XCTAssertEqual(try databasePath(.default), "/support/com%2etest%2e!app/!key!value!storage!/i/.KeyValueStorage.sqlite")
    }

    func testTheAppsFolderIsItsBundleIDOrProcessName() throws {
        locator.identifier = nil
        XCTAssertEqual(try databasePath(.own(namespace: "name")), "/support/my%20tool/name!/i/.KeyValueStorage.sqlite")
    }

    func testMissingBaseDirectoriesThrowTheirDirectory() {
        locator.directories = [:]

        assertThrows(SQLiteStorage.Error.directoryNotFound(.applicationSupportDirectory)) {
            try databasePath(.own(namespace: "name"))
        }

        assertThrows(SQLiteStorage.Error.directoryNotFound(.cachesDirectory)) {
            try databasePath(.own(.cache, namespace: "name"))
        }
    }

    func testAMissingGroupContainerOrAnEmptyIdThrowsTheId() {
        // macOS returns a container for any id, the empty one included
        locator.groupDirectories[""] = URL(fileURLWithPath: "/empty", isDirectory: true)

        assertThrows(SQLiteStorage.Error.groupDirectoryNotFound("group.other")) {
            try databasePath(.appGroup(id: "group.other", namespace: "name"))
        }

        assertThrows(SQLiteStorage.Error.groupDirectoryNotFound("")) {
            try databasePath(.appGroup(id: "", namespace: "name"))
        }
    }

    func testEveryScopesDatabaseIsInTheFileStoragesFolderForTheSameScope() throws {
        let fileLocator = FixedDirectoriesFileLocator()
        let names = (0..<128).map { String(UnicodeScalar(UInt8($0))) } + ["", "KeyValueStorage", "a/b", "\u{E9}", "e\u{301}", "🙂"]
        let protections: [(SQLiteStorage.Protection, FileStorage.Protection)] = [
            (.inherited, .inherited), (.none, .none), (.untilFirstUnlock, .untilFirstUnlock), (.whileLocked, .whileLocked), (.whileLockedUnlessOpen, .whileLockedUnlessOpen)
        ]
        let retentions: [(SQLiteStorage.Retention, FileStorage.Retention)] = [(.persistent, .persistent), (.cache, .cache), (.temporary, .temporary)]

        for name in names {
            for (protection, fileProtection) in protections {
                for (retention, fileRetention) in retentions {
                    let database = try locator.databaseURL(for: .own(retention, protection: protection, namespace: .init(name)))
                    let folder = try fileLocator.directory(for: .own(fileRetention, protection: fileProtection, namespace: .init(name)))
                    XCTAssertEqual(database.deletingLastPathComponent(), folder, name.debugDescription)
                }

                let database = try locator.databaseURL(for: .appGroup(id: "group.test", protection: protection, namespace: .init(name)))
                let folder = try fileLocator.directory(for: .appGroup(id: "group.test", protection: fileProtection, namespace: .init(name)))
                XCTAssertEqual(database.deletingLastPathComponent(), folder, name.debugDescription)
            }
        }
    }

    // MARK: Namespaces

    func testNamespacesLongerThanAFolderNameThrow() throws {
        XCTAssertNoThrow(try databasePath(.own(namespace: .init(String(repeating: "a", count: 254)))))

        let name = SQLiteStorage.Namespace(String(repeating: "a", count: 255))
        assertThrows(SQLiteStorage.Error.invalidNamespace(name)) {
            try databasePath(.own(namespace: name))
        }
    }

    func testNamespaceIsCheckedBeforeTheEnvironment() {
        let name = SQLiteStorage.Namespace(String(repeating: "A", count: 128))
        locator.directories = [:]

        assertThrows(SQLiteStorage.Error.invalidNamespace(name)) {
            try databasePath(.own(namespace: name))
        }

        assertThrows(SQLiteStorage.Error.invalidNamespace(name)) {
            try databasePath(.appGroup(id: "group.other", namespace: name))
        }
    }

    // MARK: Keys

    func testKeysAreStoredAsTheyAre() {
        for key in ["", "key", "Key", "a/b", "a\0b", "\u{E9}", "e\u{301}", "🙂"] {
            XCTAssertTrue(locator.storedKey(forKey: .init(key), in: .default).utf8.elementsEqual(key.utf8), key.debugDescription)
        }
    }

    // MARK: Helpers

    private func databasePath(_ scope: SQLiteStorage.Scope) throws(SQLiteStorage.Error) -> String {
        try locator.databaseURL(for: scope).path
    }
}
