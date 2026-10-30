//
//  UserDefaultsIntegrationTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import XCTest
import Foundation
import KeyValueStorage // not @testable: real UserDefaults through the public API

/// The default backing store and locator against real `UserDefaults`, in the own suite of a test app identifier, emptied after each test.
/// One suite for every test: the system writes an emptied suite's file back after it's deleted, so a suite per test leaves files behind.
final class UserDefaultsIntegrationTests: XCTestCase {
    private let scope = UserDefaultsStorage.Scope.own(namespace: "ns")
    private let locator = TestUserDefaultsLocator(bundleIdentifier: "UserDefaultsIntegrationTests")
    /// The test suite, read directly.
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        let suiteName = try locator.suiteName(for: scope)
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
    }

    // MARK: Values

    func testValuesPersistInTheSuiteAcrossInstances() throws {
        // When
        try storage().save(Data([1]), forKey: "key")

        // Then
        XCTAssertEqual(try storage().fetch(forKey: "key"), Data([1]))
        XCTAssertEqual(defaults.data(forKey: "ns!/key"), Data([1]))
    }

    func testStoredKeysAreTheLocatorsExactBytes() throws {
        // Given
        let storage = try storage()
        let other = try self.storage(.own(namespace: "a/b"))

        // When
        try storage.save(Data([1]), forKey: "a/b")
        try other.save(Data([2]), forKey: "c")
        try storage.save(Data([3]), forKey: "\u{E9}")
        try storage.save(Data([4]), forKey: "e\u{301}")
        try storage.save(Data([5]), forKey: "")

        // Then: the two spellings of `é` are two keys, as the suite compares bytes
        XCTAssertEqual(defaults.data(forKey: "ns!/a/b"), Data([1]))
        XCTAssertEqual(defaults.data(forKey: "a%2Fb!/c"), Data([2]))
        XCTAssertEqual(storage.fetch(forKey: "\u{E9}"), Data([3]))
        XCTAssertEqual(storage.fetch(forKey: "e\u{301}"), Data([4]))
        XCTAssertEqual(storage.fetch(forKey: ""), Data([5]))
    }

    func testOwnScopesUseTheAppsOwnSuiteNotTheStandardOne() throws {
        // When
        try storage().save(Data([1]), forKey: "key")

        // Then
        XCTAssertEqual(defaults.data(forKey: "ns!/key"), Data([1]))
        XCTAssertNil(UserDefaults.standard.object(forKey: "ns!/key"))
    }

    // MARK: Other Code's Values

    func testAValueOfAnotherTypeIsNeverReplacedOrRemoved() throws {
        // Given
        let storage = try storage()
        defaults.set("text", forKey: "ns!/key")

        // When
        let fetched = storage.fetch(forKey: "key")
        storage.delete(forKey: "key")
        storage.clear()

        // Then
        XCTAssertNil(fetched)
        assertKeyOccupied("ns!/key") { try storage.save(Data([1]), forKey: "key") }
        XCTAssertEqual(defaults.string(forKey: "ns!/key"), "text")
    }

    func testARegisteredDefaultOfAnotherTypeOccupiesTheKey() throws {
        // Given: registered defaults are process-wide, so the key is this test's own
        let key = "registered-\(UUID().uuidString)"
        UserDefaults.standard.register(defaults: ["ns!/\(key)": "text"])

        // When - Then
        assertKeyOccupied("ns!/\(key)") { try storage().save(Data([1]), forKey: .init(key)) }
    }

    func testClearRemovesExactlyTheScopesValues() throws {
        // Given: two namespaces in one suite, next to other code's data, without the library's mark, and values of other types
        let storage = try storage()
        let other = try self.storage(.own(namespace: "other"))
        try storage.save(Data([1]), forKey: "key")
        try other.save(Data([2]), forKey: "key")
        defaults.set(Data([3]), forKey: "ns/key")
        defaults.set("text", forKey: "ns!/text")
        let globalKeys = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?.keys.sorted()

        // When
        storage.clear()

        // Then
        XCTAssertNil(storage.fetch(forKey: "key"))
        XCTAssertEqual(other.fetch(forKey: "key"), Data([2]))
        XCTAssertEqual(defaults.data(forKey: "ns/key"), Data([3]))
        XCTAssertEqual(defaults.string(forKey: "ns!/text"), "text")
        XCTAssertEqual(UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?.keys.sorted(), globalKeys)
    }

    // MARK: Suites

    func testGroupIdsThatAreTheGlobalDomainTheAppsSuiteOrEmptyThrow() throws {
        let ownSuiteName = try locator.suiteName(for: scope)
        for groupId in ["", UserDefaults.globalDomain, ".GlobalPreferences", "kCFPreferencesAnyApplication", "Apple Global Domain", ownSuiteName] {
            XCTAssertThrowsError(try storage(.appGroup(id: groupId, namespace: "ns"))) { error in
                guard case .invalidSuiteName(groupId)? = error as? UserDefaultsStorage.Error else {
                    return XCTFail("Unexpected \(error)")
                }
            }
        }
    }

    func testTheLocatorsLookupsReturnTheSystems() {
        let locator = DefaultUserDefaultsLocator()

        XCTAssertEqual(locator.bundleIdentifier, Bundle.main.bundleIdentifier)
        XCTAssertEqual(locator.processName, ProcessInfo.processInfo.processName)
    }

    // MARK: Helpers

    private func storage(_ scope: UserDefaultsStorage.Scope? = nil) throws(UserDefaultsStorage.Error) -> UserDefaultsStorage {
        try UserDefaultsStorage(scope: scope ?? self.scope, backingStore: DefaultUserDefaultsBackingStoreWrapper(), locator: locator)
    }

    private func assertKeyOccupied(_ storedKey: String, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard case .keyOccupied(storedKey)? = error as? UserDefaultsStorage.Error else {
                return XCTFail("Expected .keyOccupied(\(storedKey)), got \(error)", file: file, line: line)
            }
        }
    }
}
