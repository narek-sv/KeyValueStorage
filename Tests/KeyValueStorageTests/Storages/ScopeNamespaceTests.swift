//
//  ScopeNamespaceTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 02.11.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

/// Every scope case takes its namespace as a `String` too: the same scope, with the same defaults, as the case with that
/// `ExactString`.
final class ScopeNamespaceTests: XCTestCase {
    /// A namespace made at runtime, with a combining mark, which a normalizing conversion would change.
    private let namespace = "user-\(42)-e\u{301}"

    private var exact: ExactString {
        ExactString(namespace)
    }

    func testInMemoryScopes() {
        XCTAssertEqual(InMemoryStorage.Scope.own(namespace: namespace), .own(namespace: exact))
    }

    func testUserDefaultsScopes() {
        typealias Scope = UserDefaultsStorage.Scope
        XCTAssertEqual(Scope.own(namespace: namespace), .own(namespace: exact))
        XCTAssertEqual(Scope.appGroup(id: "group", namespace: namespace), .appGroup(id: "group", namespace: exact))
    }

    func testKeychainScopes() {
        typealias Scope = KeychainStorage.Scope
        XCTAssertEqual(Scope.own(namespace: namespace), .own(protection: .whenUnlocked, namespace: exact))
        XCTAssertEqual(Scope.own(protection: .afterFirstUnlock, namespace: namespace), .own(protection: .afterFirstUnlock, namespace: exact))
        XCTAssertEqual(Scope.appGroup(id: "group", namespace: namespace), .appGroup(id: "group", protection: .whenUnlocked, namespace: exact))
        XCTAssertEqual(Scope.appGroup(id: "group", protection: .whenPasscodeSetThisDeviceOnly, namespace: namespace),
                       .appGroup(id: "group", protection: .whenPasscodeSetThisDeviceOnly, namespace: exact))
        XCTAssertEqual(Scope.iCloud(.own, namespace: namespace), .iCloud(.own, protection: .whenUnlocked, namespace: exact))
        XCTAssertEqual(Scope.iCloud(.appGroup(id: "group"), protection: .afterFirstUnlock, namespace: namespace),
                       .iCloud(.appGroup(id: "group"), protection: .afterFirstUnlock, namespace: exact))
    }

    func testFileScopes() {
        typealias Scope = FileStorage.Scope
        XCTAssertEqual(Scope.own(namespace: namespace), .own(.persistent, protection: .inherited, namespace: exact))
        XCTAssertEqual(Scope.own(.cache, protection: .whenUnlocked, namespace: namespace), .own(.cache, protection: .whenUnlocked, namespace: exact))
        XCTAssertEqual(Scope.appGroup(id: "group", namespace: namespace), .appGroup(id: "group", protection: .inherited, namespace: exact))
        XCTAssertEqual(Scope.appGroup(id: "group", protection: .none, namespace: namespace), .appGroup(id: "group", protection: .none, namespace: exact))
    }

    func testSQLiteScopes() {
        typealias Scope = SQLiteStorage.Scope
        XCTAssertEqual(Scope.own(namespace: namespace), .own(.persistent, protection: .inherited, namespace: exact))
        XCTAssertEqual(Scope.own(.temporary, protection: .whenUnlockedOrOpen, namespace: namespace),
                       .own(.temporary, protection: .whenUnlockedOrOpen, namespace: exact))
        XCTAssertEqual(Scope.appGroup(id: "group", namespace: namespace), .appGroup(id: "group", protection: .inherited, namespace: exact))
        XCTAssertEqual(Scope.appGroup(id: "group", protection: .afterFirstUnlock, namespace: namespace),
                       .appGroup(id: "group", protection: .afterFirstUnlock, namespace: exact))
    }

    func testUbiquitousScopes() {
        if #available(watchOS 9.0, *) {
            XCTAssertEqual(UbiquitousStorage.Scope.iCloud(.own, namespace: namespace), .iCloud(.own, namespace: exact))
        }
    }

    func testANamespaceKeepsItsExactBytes() {
        let composed = "\u{E9}"
        let decomposed = "e\u{301}"
        XCTAssertNotEqual(FileStorage.Scope.own(namespace: composed), .own(namespace: decomposed))
        XCTAssertEqual(FileStorage.Scope.own(namespace: decomposed), .own(namespace: ExactString(decomposed)))
    }
}
