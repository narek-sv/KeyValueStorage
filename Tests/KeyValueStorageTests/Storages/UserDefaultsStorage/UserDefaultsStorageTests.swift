//
//  UserDefaultsStorageTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

/// The storage's rules against a mock suite; the real one is in `UserDefaultsIntegrationTests`.
final class UserDefaultsStorageTests: XCTestCase {
    private let suite = UserDefaultsSuiteMock()
    private let locator = UserDefaultsLocatorStub()
    private let scope = UserDefaultsStorage.Scope.own(namespace: "prefix")
    private let data = Data([0xAA, 0xBB])
    /// Values of other types, as other code can put under any key.
    private let foreignValues: [Any] = ["text", 1, true, Date(timeIntervalSince1970: 0), ["a"], ["a": 1]]

    private lazy var backingStore: UserDefaultsBackingStoreMock = {
        let backingStore = UserDefaultsBackingStoreMock()
        backingStore.suites["located"] = suite
        return backingStore
    }()

    // MARK: Initializers

    func testInitOpensTheLocatorsSuite() throws {
        // When
        _ = try makeStorage()

        // Then
        XCTAssertEqual(locator.calls, [.suiteName(scope)])
        XCTAssertEqual(backingStore.calls, ["located"])
    }

    func testInitThrowsTheLocatorsErrorBeforeOpeningASuite() {
        // Given
        locator.suiteNameError = .invalidSuiteName("group.rejected")

        // When - Then
        assertThrows(UserDefaultsStorage.Error.invalidSuiteName("group.rejected")) { try makeStorage() }
        XCTAssertEqual(backingStore.calls, [])
    }

    func testInitThrowsForASuiteNameUserDefaultsRejects() {
        // Given
        locator.suiteName = "rejected"

        // When - Then
        assertThrows(UserDefaultsStorage.Error.invalidSuiteName("rejected")) { try makeStorage() }
    }

    func testScopeIsTheOneGiven() throws {
        XCTAssertEqual(try makeStorage().scope, scope)
    }

    // MARK: Only Data Is A Value

    func testFetchReturnsTheDataAtTheLocatorsStoredKey() throws {
        // Given
        suite.values["located-key"] = data
        let storage = try makeStorage()

        // When - Then
        XCTAssertEqual(storage.fetch(forKey: "key"), data)
        XCTAssertNil(storage.fetch(forKey: "other"))
    }

    func testAValueOfAnotherTypeIsNeverAValueAndNeverReplacedOrRemoved() throws {
        for value in foreignValues {
            // Given
            let suite = UserDefaultsSuiteMock()
            suite.values["located-key"] = value
            backingStore.suites["located"] = suite
            locator.keys = ["located-key": "key"]
            let storage = try makeStorage()

            // When
            let fetched = storage.fetch(forKey: "key")
            storage.delete(forKey: "key")
            storage.clear()

            // Then
            XCTAssertNil(fetched)
            assertThrows(UserDefaultsStorage.Error.keyOccupied("located-key")) { try storage.save(data, forKey: "key") }
            XCTAssertEqual(suite.calls, [.read("located-key"), .read("located-key"), .keys, .read("located-key"), .read("located-key")])
            XCTAssertTrue((suite.values["located-key"] as AnyObject).isEqual(value), "\(value)")
        }
    }

    func testSaveWritesAndReplacesData() throws {
        // Given
        let storage = try makeStorage()

        // When
        try storage.save(data, forKey: "key")
        try storage.save(Data([1]), forKey: "key")

        // Then
        XCTAssertEqual(suite.values["located-key"] as? Data, Data([1]))
        XCTAssertEqual(suite.calls, [.read("located-key"), .write(data, "located-key"), .read("located-key"), .write(Data([1]), "located-key")])
    }

    func testDeleteRemovesTheData() throws {
        // Given
        suite.values = ["located-key": data, "located-other": data]
        let storage = try makeStorage()

        // When
        storage.delete(forKey: "key")
        storage.delete(forKey: "missing")

        // Then
        XCTAssertEqual(suite.values.keys.sorted(), ["located-other"])
        XCTAssertEqual(suite.calls, [.read("located-key"), .remove("located-key"), .read("located-missing")])
    }

    // MARK: Clear

    func testClearRemovesOnlyTheDataAtStoredKeysTheLocatorClaims() throws {
        // Given: the scope's values, next to other code's data and a value of another type under a claimed key
        suite.values = ["located-a": data, "located-b": data, "foreign": data, "located-text": "text"]
        locator.keys = ["located-a": "a", "located-b": "b", "located-text": "text"]

        // When
        try makeStorage().clear()

        // Then
        XCTAssertEqual(suite.values.keys.sorted(), ["foreign", "located-text"])
    }

    func testClearSkipsStoredKeysWhoseKeyHasAnotherStoredKey() throws {
        // Given: a locator whose two methods disagree, by a key or only by how `é` is written
        suite.values = ["located-stale": data, "located-e\u{301}": data]
        locator.keys = ["located-stale": "other", "located-e\u{301}": "\u{E9}"]

        // When
        try makeStorage().clear()

        // Then
        XCTAssertEqual(suite.calls, [.keys])
    }

    // MARK: Set

    func testSetSavesAValueAndDeletesNil() throws {
        // Given
        let storage = try makeStorage()

        // When
        try storage.set(data, forKey: "key")
        let saved = suite.values["located-key"] as? Data
        try storage.set(nil, forKey: "key")

        // Then
        XCTAssertEqual(saved, data)
        XCTAssertNil(suite.values["located-key"])
    }

    // MARK: Helpers

    private func makeStorage() throws(UserDefaultsStorage.Error) -> UserDefaultsStorage {
        try UserDefaultsStorage(scope: scope, backingStore: backingStore, locator: locator)
    }
}
