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
    private let scope = KeychainStorage.Scope.own(namespace: "name")
    private let data = Data([0xAA, 0xBB])

    // MARK: Locator

    func testQueriesUseExactlyTheLocatorsNames() throws {
        // When
        try makeStorage().save(data, forKey: "key")

        // Then
        XCTAssertEqual(locator.calls, [.service(scope), .accessGroup(scope), .account("key", scope)])
        XCTAssertEqual(backingStore.items, [item("key", data: data, accessibility: .whenUnlocked)])
    }

    func testScopeIsTheOneGiven() {
        XCTAssertEqual(makeStorage().scope, scope)
    }

    // MARK: Queries

    func testSaveUpdatesTheKeysItemAndAddsItOnlyIfThereIsNone() throws {
        // Given
        let storage = makeStorage(.iCloud(.own, protection: .untilFirstUnlock, namespace: "name"))

        // When
        try storage.save(data, forKey: "key")
        try storage.save(Data([1]), forKey: "key")

        // Then: no read first, and accessibility only in what's written
        let item = query(account: "located-key", synchronizable: .yes)
        XCTAssertEqual(backingStore.calls, [
            .update(item, KeychainQuery(accessibility: .afterFirstUnlock, valueData: data)),
            .add(query(account: "located-key", synchronizable: .yes, accessibility: .afterFirstUnlock, valueData: data)),
            .update(item, KeychainQuery(accessibility: .afterFirstUnlock, valueData: Data([1])))
        ])
    }

    func testFetchDeleteAndClearAreOneCallEach() throws {
        // Given
        backingStore.items = [item("key", data: data)]
        let storage = makeStorage()

        // When
        _ = try storage.fetch(forKey: "key")
        try storage.delete(forKey: "key")
        try storage.clear()

        // Then: delete and clear never read first
        XCTAssertEqual(backingStore.calls, [
            .read(query(account: "located-key", synchronizable: .no, returnData: true, matchLimit: .one)),
            .remove(query(account: "located-key", synchronizable: .no)),
            .remove(query(account: nil, synchronizable: .no))
        ])
    }

    func testTheScopesProtectionSetsTheItemsAccessibilityAndSync() throws {
        let scopes: [(KeychainStorage.Scope, KeychainQuery.Accessibility, KeychainQuery.Synchronizable)] = [
            (.own(protection: .untilFirstUnlock, namespace: "name"), .afterFirstUnlock, .no),
            (.own(protection: .untilFirstUnlockThisDeviceOnly, namespace: "name"), .afterFirstUnlockThisDeviceOnly, .no),
            (.own(protection: .whileLocked, namespace: "name"), .whenUnlocked, .no),
            (.own(protection: .whileLockedThisDeviceOnly, namespace: "name"), .whenUnlockedThisDeviceOnly, .no),
            (.appGroup(id: "group", protection: .whileLockedOrWithoutPasscode, namespace: "name"), .whenPasscodeSetThisDeviceOnly, .no),
            (.iCloud(.own, protection: .untilFirstUnlock, namespace: "name"), .afterFirstUnlock, .yes),
            (.iCloud(.appGroup(id: "group"), protection: .whileLocked, namespace: "name"), .whenUnlocked, .yes)
        ]

        for (scope, accessibility, synchronizable) in scopes {
            // Given
            let backingStore = KeychainBackingStoreMock()

            // When
            try KeychainStorage(scope: scope, backingStore: backingStore, locator: locator).save(data, forKey: "key")

            // Then
            XCTAssertEqual(backingStore.calls.last, .add(query(account: "located-key", synchronizable: synchronizable, accessibility: accessibility, valueData: data)), "\(scope)")
        }
    }

    func testSyncedScopesNeverReachTheLocalItemsOfTheirService() throws {
        // Given: two scopes with one service, told apart by sync alone
        let local = makeStorage(.own(namespace: "name"))
        let synced = makeStorage(.iCloud(.own, namespace: "name"))

        // When
        try synced.save(Data([1]), forKey: "key")
        try local.save(Data([2]), forKey: "key")

        // Then
        XCTAssertEqual(try synced.fetch(forKey: "key"), Data([1]))
        XCTAssertEqual(try local.fetch(forKey: "key"), Data([2]))

        // When
        try local.clear()

        // Then
        XCTAssertEqual(try synced.fetch(forKey: "key"), Data([1]))
        XCTAssertNil(try local.fetch(forKey: "key"))
    }

    // MARK: Values

    func testFetchReturnsTheKeysData() throws {
        // Given
        backingStore.items = [item("key", data: data)]
        let storage = makeStorage()

        // When - Then
        XCTAssertEqual(try storage.fetch(forKey: "key"), data)
        XCTAssertNil(try storage.fetch(forKey: "other"))
    }

    func testAnItemWithoutDataFetchesAsNilAndIsReplacedAndRemovedLikeAValue() throws {
        // Given
        backingStore.items = [item("key", data: nil), item("other", data: nil)]
        let storage = makeStorage()

        // When - Then
        XCTAssertNil(try storage.fetch(forKey: "key"))

        try storage.save(data, forKey: "key")
        XCTAssertEqual(backingStore.items, [item("key", data: data, accessibility: .whenUnlocked), item("other", data: nil)])

        try storage.delete(forKey: "key")
        XCTAssertEqual(backingStore.items, [item("other", data: nil)])

        try storage.clear()
        XCTAssertEqual(backingStore.items, [])
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

    func testClearRemovesEveryItemOfTheScopeAndNothingElse() throws {
        // Given: the scope's items, one without data, next to a synced item of its service and another service's item
        let synced = item("b", data: data, synchronizable: true)
        let other = Item(service: "other", account: "located-key", accessGroup: "located.group", synchronizable: false, data: data)
        backingStore.items = [item("a", data: data), synced, item("empty", data: nil), other]

        // When
        try makeStorage().clear()

        // Then
        XCTAssertEqual(backingStore.items, [synced, other])
    }

    func testClearWithoutItemsSucceeds() throws {
        // When
        try makeStorage().clear()

        // Then
        XCTAssertEqual(backingStore.calls.count, 1)
    }

    // MARK: Errors

    func testALockedDeviceIsProtectedDataUnavailableAndOtherStatusesKeepTheirCode() {
        let errors: [(KeychainOperationStatus, KeychainStorage.Error)] = [
            (.interactionNotAllowed, .protectedDataUnavailable),
            (.missingEntitlement, .keychain(status: errSecMissingEntitlement)),
            (.duplicate, .keychain(status: errSecDuplicateItem)),
            (.other(errSecAuthFailed), .keychain(status: errSecAuthFailed))
        ]

        for (status, expected) in errors {
            XCTAssertEqual(String(reflecting: KeychainStorage.Error(status)), String(reflecting: expected), "\(status)")
        }
    }

    func testStatusesKeepTheirCode() {
        let codes = [errSecSuccess, errSecItemNotFound, errSecDuplicateItem, errSecInteractionNotAllowed, errSecMissingEntitlement, errSecAuthFailed, -1]
        for code in codes {
            XCTAssertEqual(KeychainOperationStatus(status: code).code, code)
        }

        XCTAssertEqual(KeychainOperationStatus(status: errSecAuthFailed), .other(errSecAuthFailed))
        XCTAssertEqual(KeychainOperationStatus(status: errSecInteractionNotAllowed), .interactionNotAllowed)
    }

    func testEveryKeychainFailureIsReported() throws {
        let operations: [(KeychainBackingStoreMock.Operation, (KeychainStorage) throws -> Void)] = [
            (.read, { _ = try $0.fetch(forKey: "key") }),
            (.update, { try $0.save(Data([1]), forKey: "key") }),
            (.add, { try $0.save(Data([1]), forKey: "new") }),
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
            assertThrows(KeychainStorage.Error.protectedDataUnavailable) { try body(storage) }
            XCTAssertEqual(backingStore.items, [item("key", data: data)])
        }
    }

    func testAnItemAddedBetweenSavesUpdateAndAddIsReplaced() throws {
        // Given: another call adds the item after the update found none
        let other = item("key", data: Data([9]))
        backingStore.beforeAdd = { [backingStore] in backingStore.items.append(other) }

        // When
        try makeStorage().save(data, forKey: "key")

        // Then: the last save wins
        XCTAssertEqual(backingStore.items.map(\.data), [data])
        XCTAssertEqual(backingStore.calls.map(operation), [.update, .add, .update])
    }

    func testAFailingUpdateAfterADuplicateIsReported() {
        // Given: another call adds the item, and the second update fails
        let other = item("key", data: Data([9]))
        backingStore.beforeAdd = { [backingStore] in
            backingStore.items.append(other)
            backingStore.failures[.update] = .missingEntitlement
        }

        // When - Then
        assertThrows(KeychainStorage.Error.keychain(status: errSecMissingEntitlement)) { try makeStorage().save(data, forKey: "key") }
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
        // Given: one namespace in every kind of scope, App Groups among them the app's default access group,
        // whose items `.own` queries reach, next to another namespace and another protection
        let scopes: [KeychainStorage.Scope] = [
            .own(namespace: "auth"),
            .own(namespace: "other"),
            .own(protection: .untilFirstUnlock, namespace: "auth"),
            .appGroup(id: "group.com.app", namespace: "auth"),
            .appGroup(id: backingStore.defaultGroup, namespace: "auth"),
            .iCloud(.own, namespace: "auth"),
            .iCloud(.appGroup(id: backingStore.defaultGroup), namespace: "auth")
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
        try storages[0].clear()

        // Then
        XCTAssertNil(try storages[0].fetch(forKey: "token"))
        XCTAssertEqual(backingStore.items.count, scopes.count - 1)
    }

    // MARK: Helpers

    private func makeStorage(_ scope: KeychainStorage.Scope? = nil) -> KeychainStorage {
        KeychainStorage(scope: scope ?? self.scope, backingStore: backingStore, locator: locator)
    }

    private func operation(_ call: KeychainBackingStoreMock.Call) -> KeychainBackingStoreMock.Operation {
        switch call {
        case .read:     return .read
        case .add:      return .add
        case .update:   return .update
        case .remove:   return .remove
        }
    }

    private func item(
        _ key: String,
        data: Data?,
        synchronizable: Bool = false,
        accessibility: KeychainQuery.Accessibility? = nil
    ) -> Item {
        Item(service: "located-service", account: "located-\(key)", accessGroup: "located.group", synchronizable: synchronizable,
             accessibility: accessibility, data: data)
    }

    private func query(
        account: String?,
        synchronizable: KeychainQuery.Synchronizable,
        accessibility: KeychainQuery.Accessibility? = nil,
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
            returnData: returnData,
            matchLimit: matchLimit,
            valueData: valueData
        )
    }
}
