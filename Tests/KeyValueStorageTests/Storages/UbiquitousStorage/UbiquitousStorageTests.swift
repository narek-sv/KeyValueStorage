//
//  UbiquitousStorageTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

/// The storage's rules against a mock store. The real store needs an iCloud entitlement and an Apple Account,
/// which test bundles don't have: without them it keeps nothing.
@available(watchOS 9.0, *)
final class UbiquitousStorageTests: XCTestCase {
    private let backingStore = UbiquitousBackingStoreMock()
    private let locator = UbiquitousLocatorStub()
    private let scope = UbiquitousStorage.Scope.shared(namespace: .keyPrefix(named: "prefix"))
    private let data = Data([0xAA, 0xBB])
    /// Values of other types, as other code can put under any key.
    private let foreignValues: [Any] = ["text", 1, true, Date(timeIntervalSince1970: 0), ["a"], ["a": 1]]

    // MARK: Scope

    func testScopeIsTheOneGiven() {
        XCTAssertEqual(makeStorage().scope, scope)
    }

    // MARK: Locator

    func testLocatorErrorsStopBeforeTheStore() {
        // Given
        locator.storedKeyError = .invalidKey("key")
        let storage = makeStorage()

        // When - Then
        assertThrows(UbiquitousStorage.Error.invalidKey("key")) { try storage.fetch(forKey: "key") }
        assertThrows(UbiquitousStorage.Error.invalidKey("key")) { try storage.save(data, forKey: "key") }
        assertThrows(UbiquitousStorage.Error.invalidKey("key")) { try storage.delete(forKey: "key") }
        XCTAssertEqual(backingStore.calls, [])
    }

    // MARK: Only Data Is A Value

    func testFetchReturnsTheDataAtTheLocatorsStoredKey() throws {
        // Given
        backingStore.values["located-key"] = data
        let storage = makeStorage()

        // When - Then
        XCTAssertEqual(try storage.fetch(forKey: "key"), data)
        XCTAssertNil(try storage.fetch(forKey: "other"))
    }

    func testAValueOfAnotherTypeIsNeverAValueAndNeverReplacedOrRemoved() throws {
        for value in foreignValues {
            // Given
            let backingStore = UbiquitousBackingStoreMock()
            backingStore.values["located-key"] = value
            locator.keys = ["located-key": "key"]
            let storage = UbiquitousStorage(scope: scope, backingStore: backingStore, locator: locator)

            // When
            let fetched = try storage.fetch(forKey: "key")
            try storage.delete(forKey: "key")
            storage.clear()

            // Then
            XCTAssertNil(fetched)
            assertThrows(UbiquitousStorage.Error.keyOccupied("located-key")) { try storage.save(data, forKey: "key") }
            XCTAssertEqual(backingStore.calls, [.read("located-key"), .read("located-key"), .keys, .read("located-key"), .read("located-key")])
            XCTAssertTrue((backingStore.values["located-key"] as AnyObject).isEqual(value), "\(value)")
        }
    }

    func testSaveWritesAndReplacesData() throws {
        // Given
        let storage = makeStorage()

        // When
        try storage.save(data, forKey: "key")
        try storage.save(Data([1]), forKey: "key")

        // Then
        XCTAssertEqual(backingStore.values["located-key"] as? Data, Data([1]))
        XCTAssertEqual(backingStore.calls, [.read("located-key"), .write(data, "located-key"), .read("located-key"), .write(Data([1]), "located-key")])
    }

    func testValuesOverOneMegabyteStopBeforeTheStore() throws {
        // Given
        let storage = makeStorage()
        let limit = Data(count: 1024 * 1024)

        // When - Then
        try storage.save(limit, forKey: "key")
        assertThrows(UbiquitousStorage.Error.valueTooLarge(key: "key", size: limit.count + 1)) { try storage.save(limit + [0], forKey: "key") }
        XCTAssertEqual(backingStore.calls.count, 2)
    }

    func testDeleteRemovesTheData() throws {
        // Given
        backingStore.values = ["located-key": data, "located-other": data]
        let storage = makeStorage()

        // When
        try storage.delete(forKey: "key")
        try storage.delete(forKey: "missing")

        // Then
        XCTAssertEqual(backingStore.values.keys.sorted(), ["located-other"])
        XCTAssertEqual(backingStore.calls, [.read("located-key"), .remove("located-key"), .read("located-missing")])
    }

    // MARK: Clear

    func testClearRemovesOnlyTheDataAtStoredKeysTheLocatorClaims() {
        // Given: the scope's values, next to other code's data and a value of another type under a claimed key
        backingStore.values = ["located-a": data, "located-b": data, "foreign": data, "located-text": "text"]
        locator.keys = ["located-a": "a", "located-b": "b", "located-text": "text"]

        // When
        makeStorage().clear()

        // Then
        XCTAssertEqual(backingStore.values.keys.sorted(), ["foreign", "located-text"])
    }

    func testClearSkipsStoredKeysWhoseKeyHasAnotherStoredKey() {
        // Given: a locator whose two methods disagree, by a key or only by how `é` is written
        backingStore.values = ["located-stale": data, "located-e\u{301}": data]
        locator.keys = ["located-stale": "other", "located-e\u{301}": "\u{E9}"]

        // When
        makeStorage().clear()

        // Then
        XCTAssertEqual(backingStore.calls, [.keys])
    }

    func testClearSkipsStoredKeysWhoseKeyIsInvalid() {
        // Given
        backingStore.values = ["located-key": data]
        locator.keys = ["located-key": "key"]
        locator.storedKeyError = .invalidKey("key")

        // When
        makeStorage().clear()

        // Then
        XCTAssertEqual(backingStore.calls, [.keys])
    }

    // MARK: Set And Synchronize

    func testSetSavesAValueAndDeletesNil() throws {
        // Given
        let storage = makeStorage()

        // When
        try storage.set(data, forKey: "key")
        let saved = backingStore.values["located-key"] as? Data
        try storage.set(nil, forKey: "key")

        // Then
        XCTAssertEqual(saved, data)
        XCTAssertNil(backingStore.values["located-key"])
    }

    func testSynchronizeReturnsTheStoresResult() {
        // Given
        let storage = makeStorage()

        // When - Then
        XCTAssertTrue(storage.synchronize())
        backingStore.synchronizes = false
        XCTAssertFalse(storage.synchronize())
        XCTAssertEqual(backingStore.calls, [.synchronize, .synchronize])
    }

    // MARK: Helpers

    private func makeStorage() -> UbiquitousStorage {
        UbiquitousStorage(scope: scope, backingStore: backingStore, locator: locator)
    }
}
