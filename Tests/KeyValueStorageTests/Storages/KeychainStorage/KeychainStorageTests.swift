//
//  KeychainStorageTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import XCTest
import Foundation
import Security
@testable import KeyValueStorage

/// The storage's rules against an in-memory keychain; the real one is in KeychainHost's `KeychainIntegrationTests`.
final class KeychainStorageTests: XCTestCase {
    private typealias Item = KeychainBackingStoreMock.Item

    private let backingStore = KeychainBackingStoreMock()
    private let locator = KeychainLocatorStub()
    private let scope = KeychainStorage.Scope.app(namespace: .service(named: "name"))
    private let data = Data([0xAA, 0xBB])

    // MARK: Locator

    func testQueriesUseExactlyTheLocatorsNames() throws {
        // When
        try makeStorage().save(data, forKey: "key")

        // Then
        XCTAssertEqual(locator.calls.prefix(2), [.service(scope), .accessGroup(scope)])
        XCTAssertEqual(backingStore.items, [item("key", data: data, accessibility: .whenUnlocked)])
    }

    func testScopeIsTheOneGiven() {
        XCTAssertEqual(makeStorage().scope, scope)
    }

    // MARK: Queries

    func testQueriesAskForTheKeysItemAndSetItsAccessibilityOnlyWhenWriting() throws {
        // Given
        let storage = makeStorage()
        let key = KeychainStorage.Key(name: "key", accessibility: .afterFirstUnlock, isSynchronizable: true)

        // When
        try storage.save(data, forKey: key)
        try storage.save(Data([1]), forKey: key)

        // Then
        let item = query(account: "located-key", synchronizable: .yes)
        XCTAssertEqual(backingStore.calls, [
            .read(query(account: "located-key", synchronizable: .yes, returnData: true, matchLimit: .one)),
            .add(query(account: "located-key", synchronizable: .yes, accessibility: .afterFirstUnlock, valueData: data)),
            .read(query(account: "located-key", synchronizable: .yes, returnData: true, matchLimit: .one)),
            .update(item, KeychainQuery(accessibility: .afterFirstUnlock, valueData: Data([1])))
        ])
    }

    func testSynchronizableKeysAreItemsOfTheirOwn() throws {
        // Given
        let storage = makeStorage()

        // When
        try storage.save(Data([1]), forKey: .init(name: "key", isSynchronizable: true))
        try storage.save(Data([2]), forKey: .init(name: "key"))

        // Then
        XCTAssertEqual(try storage.fetch(forKey: .init(name: "key", isSynchronizable: true)), Data([1]))
        XCTAssertEqual(try storage.fetch(forKey: .init(name: "key")), Data([2]))
    }

    // MARK: Only Data Is A Value

    func testFetchReturnsTheKeysData() throws {
        // Given
        backingStore.items = [item("key", data: data)]
        let storage = makeStorage()

        // When - Then
        XCTAssertEqual(try storage.fetch(forKey: "key"), data)
        XCTAssertNil(try storage.fetch(forKey: "other"))
    }

    func testAnItemWithoutDataIsNeverAValueAndNeverReplacedOrRemoved() throws {
        // Given
        backingStore.items = [item("key", data: nil)]
        let storage = makeStorage()

        // When
        let fetched = try storage.fetch(forKey: "key")
        try storage.delete(forKey: "key")
        try storage.clear()

        // Then
        XCTAssertNil(fetched)
        assertThrows(KeychainStorage.Error.keyOccupied("located-key")) { try storage.save(data, forKey: "key") }
        XCTAssertEqual(backingStore.items, [item("key", data: nil)])
    }

    func testDeleteRemovesTheKeysItem() throws {
        // Given
        backingStore.items = [item("key", data: data), item("other", data: data)]
        let storage = makeStorage()

        // When
        try storage.delete(forKey: "key")
        try storage.delete(forKey: "missing")

        // Then
        XCTAssertEqual(backingStore.items, [item("other", data: data)])
    }

    // MARK: Clear

    func testClearRemovesOnlyTheScopesItemsWithData() throws {
        // Given: the scope's items, synchronizable or not, next to one without data and another service's
        let other = Item(service: "other", account: "located-key", accessGroup: "located.group", synchronizable: false, data: data)
        backingStore.items = [item("a", data: data), item("b", data: data, synchronizable: true), item("empty", data: nil), other]

        // When
        try makeStorage().clear()

        // Then
        XCTAssertEqual(backingStore.items, [item("empty", data: nil), other])
        XCTAssertEqual(backingStore.calls.first, .read(query(account: nil, synchronizable: .any, returnAttributes: true, returnData: true, matchLimit: .all)))
    }

    func testClearRemovesNothingItCantIdentify() throws {
        // Given: a listing that isn't items, and an item without an account
        for listing in ["unexpected" as NSString, [[kSecValueData as String: data]] as NSArray] {
            let backingStore = KeychainBackingStoreMock()
            backingStore.items = [item("key", data: data)]
            backingStore.listing = listing

            // When
            try KeychainStorage(scope: scope, backingStore: backingStore, locator: locator).clear()

            // Then
            XCTAssertEqual(backingStore.items, [item("key", data: data)])
            XCTAssertEqual(backingStore.calls.count, 1)
        }
    }

    func testClearWithoutItemsDoesNothing() throws {
        // When
        try makeStorage().clear()

        // Then
        XCTAssertEqual(backingStore.calls.count, 1)
    }

    // MARK: Errors

    func testEveryKeychainFailureIsReported() throws {
        let operations: [(KeychainBackingStoreMock.Operation, (KeychainStorage) throws -> Void)] = [
            (.read, { _ = try $0.fetch(forKey: "key") }),
            (.read, { try $0.save(Data([1]), forKey: "key") }),
            (.read, { try $0.delete(forKey: "key") }),
            (.read, { try $0.clear() }),
            (.add, { try $0.save(Data([1]), forKey: "new") }),
            (.update, { try $0.save(Data([1]), forKey: "key") }),
            (.remove, { try $0.delete(forKey: "key") }),
            (.remove, { try $0.clear() })
        ]

        for (operation, body) in operations {
            // Given
            let backingStore = KeychainBackingStoreMock()
            backingStore.items = [item("key", data: data)]
            backingStore.failures[operation] = .interactionNotAllowed
            let storage = KeychainStorage(scope: scope, backingStore: backingStore, locator: locator)

            // When - Then
            assertThrows(KeychainStorage.Error.os(errSecInteractionNotAllowed)) { try body(storage) }
            XCTAssertEqual(backingStore.items, [item("key", data: data)])
        }
    }

    // MARK: Set

    func testSetSavesAValueAndDeletesNil() throws {
        // Given
        let storage = makeStorage()

        // When
        try storage.set(data, forKey: "key")
        let saved = try storage.fetch(forKey: "key")
        try storage.set(nil, forKey: "key")

        // Then
        XCTAssertEqual(saved, data)
        XCTAssertEqual(backingStore.items, [])
    }

    // MARK: Scopes

    func testScopesNeverReachEachOthersItems() throws {
        // Given: the root, a namespace, and App Groups, one of them the app's default access group,
        // whose items an app scope's queries reach
        let scopes: [KeychainStorage.Scope] = [
            .app(),
            .app(namespace: .service(named: "auth")),
            .appGroup(groupId: "group.com.app", namespace: .service(named: "auth")),
            .appGroup(groupId: backingStore.defaultGroup, namespace: .service(named: "auth")),
            .appGroup(groupId: backingStore.defaultGroup)
        ]
        let storages = scopes.map { KeychainStorage(scope: $0, backingStore: backingStore, locator: DefaultKeychainLocator()) }

        // When
        for (index, storage) in storages.enumerated() {
            try storage.save(Data([UInt8(index)]), forKey: "token")
        }

        // Then
        for (index, storage) in storages.enumerated() {
            XCTAssertEqual(try storage.fetch(forKey: "token"), Data([UInt8(index)]), "\(scopes[index])")
        }

        // When
        try storages[1].clear()

        // Then
        XCTAssertNil(try storages[1].fetch(forKey: "token"))
        XCTAssertEqual(backingStore.items.count, scopes.count - 1)
    }

    // MARK: Helpers

    private func makeStorage() -> KeychainStorage {
        KeychainStorage(scope: scope, backingStore: backingStore, locator: locator)
    }

    private func item(
        _ key: String,
        data: Data?,
        synchronizable: Bool = false,
        accessibility: KeychainStorage.Key.Accessibility? = nil
    ) -> Item {
        Item(service: "located-service", account: "located-\(key)", accessGroup: "located.group", synchronizable: synchronizable,
             accessibility: accessibility, data: data)
    }

    private func query(
        account: String?,
        synchronizable: KeychainQuery.Synchronizable,
        accessibility: KeychainStorage.Key.Accessibility? = nil,
        returnAttributes: Bool? = nil,
        returnData: Bool? = nil,
        matchLimit: KeychainQuery.MatchLimit? = nil,
        valueData: Data? = nil
    ) -> KeychainQuery {
        KeychainQuery(
            itemClass: .genericPassword,
            service: "located-service",
            account: account,
            accessGroup: "located.group",
            synchronizable: synchronizable,
            accessibility: accessibility,
            useDataProtectionKeychain: true,
            returnAttributes: returnAttributes,
            returnData: returnData,
            matchLimit: matchLimit,
            valueData: valueData
        )
    }
}
