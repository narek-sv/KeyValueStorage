//
//  UserDefaultsIntegrationTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import XCTest
import Foundation
import KeyValueStorage // not @testable: real UserDefaults through the public API

/// The default backing store and locator against real `UserDefaults`, in a suite of each test's own.
final class UserDefaultsIntegrationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    private var root: UserDefaultsStorage.Scope {
        .app(.suite(named: suiteName))
    }

    override func setUpWithError() throws {
        let suiteName = "UserDefaultsIntegrationTests-\(UUID().uuidString)"
        self.suiteName = suiteName
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
    }

    // MARK: Values

    func testValuesPersistInTheSuiteAcrossInstances() throws {
        // When
        try UserDefaultsStorage(scope: root).save(Data([1]), forKey: "key")

        // Then
        XCTAssertEqual(try UserDefaultsStorage(scope: root).fetch(forKey: "key"), Data([1]))
        XCTAssertEqual(defaults.data(forKey: "key"), Data([1]))
    }

    func testStoredKeysAreTheLocatorsExactBytes() throws {
        // Given
        let storage = try UserDefaultsStorage(scope: root)
        let namespaced = try UserDefaultsStorage(scope: namespace("ns"))

        // When
        try storage.save(Data([1]), forKey: "a/b")
        try namespaced.save(Data([2]), forKey: "a/b")
        try storage.save(Data([3]), forKey: "\u{E9}")
        try storage.save(Data([4]), forKey: "e\u{301}")
        try storage.save(Data([5]), forKey: "")

        // Then: the two spellings of `é` are two keys, as the suite compares bytes
        XCTAssertEqual(defaults.data(forKey: "a%2Fb"), Data([1]))
        XCTAssertEqual(defaults.data(forKey: "ns/a/b"), Data([2]))
        XCTAssertEqual(storage.fetch(forKey: "\u{E9}"), Data([3]))
        XCTAssertEqual(storage.fetch(forKey: "e\u{301}"), Data([4]))
        XCTAssertEqual(storage.fetch(forKey: ""), Data([5]))
    }

    func testTheStandardSuiteIsUserDefaultsStandard() throws {
        // Given
        let name = "UserDefaultsIntegrationTests-\(UUID().uuidString)"
        let storage = try UserDefaultsStorage(scope: .app(.standard, namespace: .keyPrefix(named: name)))
        defer { storage.clear() }

        // When
        try storage.save(Data([1]), forKey: "key")

        // Then
        XCTAssertEqual(UserDefaults.standard.data(forKey: "\(name)/key"), Data([1]))
    }

    // MARK: Other Code's Values

    func testAValueOfAnotherTypeIsNeverReplacedOrRemoved() throws {
        // Given
        let storage = try UserDefaultsStorage(scope: root)
        defaults.set("text", forKey: "key")

        // When
        let fetched = storage.fetch(forKey: "key")
        storage.delete(forKey: "key")
        storage.clear()

        // Then
        XCTAssertNil(fetched)
        assertKeyOccupied("key") { try storage.save(Data([1]), forKey: "key") }
        XCTAssertEqual(defaults.string(forKey: "key"), "text")
    }

    func testARegisteredDefaultOfAnotherTypeOccupiesTheKey() throws {
        // Given: registered defaults are process-wide, so the key is this test's own
        let key = "registered-\(UUID().uuidString)"
        UserDefaults.standard.register(defaults: [key: "text"])

        // When - Then
        assertKeyOccupied(key) { try UserDefaultsStorage(scope: root).save(Data([1]), forKey: .init(key)) }
    }

    func testClearRemovesExactlyTheScopesValues() throws {
        // Given: the root and two namespaces in one suite, next to other code's data and values of other types
        let storage = try UserDefaultsStorage(scope: root)
        let namespaced = try UserDefaultsStorage(scope: namespace("ns"))
        let other = try UserDefaultsStorage(scope: namespace("other"))
        try storage.save(Data([1]), forKey: "key")
        try namespaced.save(Data([2]), forKey: "key")
        try other.save(Data([3]), forKey: "key")
        defaults.set(Data([4]), forKey: "foreign/key")  // no scope's: a root key never contains `/`
        defaults.set("text", forKey: "plain")
        let globalKeys = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?.keys.sorted()

        // When
        storage.clear()

        // Then
        XCTAssertNil(storage.fetch(forKey: "key"))
        XCTAssertEqual(namespaced.fetch(forKey: "key"), Data([2]))
        XCTAssertEqual(other.fetch(forKey: "key"), Data([3]))
        XCTAssertEqual(defaults.data(forKey: "foreign/key"), Data([4]))
        XCTAssertEqual(defaults.string(forKey: "plain"), "text")
        XCTAssertEqual(UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?.keys.sorted(), globalKeys)

        // When
        namespaced.clear()

        // Then
        XCTAssertNil(namespaced.fetch(forKey: "key"))
        XCTAssertEqual(other.fetch(forKey: "key"), Data([3]))
    }

    // MARK: Suites

    func testSuiteNamesUserDefaultsRejectsThrow() {
        XCTAssertThrowsError(try UserDefaultsStorage(scope: .app(.suite(named: UserDefaults.globalDomain)))) { error in
            guard case .invalidSuiteName(UserDefaults.globalDomain)? = error as? UserDefaultsStorage.Error else {
                return XCTFail("Unexpected \(error)")
            }
        }
    }

    // MARK: Helpers

    private func namespace(_ name: String) -> UserDefaultsStorage.Scope {
        .app(.suite(named: suiteName), namespace: .keyPrefix(named: name))
    }

    private func assertKeyOccupied(_ storedKey: String, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard case .keyOccupied(storedKey)? = error as? UserDefaultsStorage.Error else {
                return XCTFail("Expected .keyOccupied(\(storedKey)), got \(error)", file: file, line: line)
            }
        }
    }
}
