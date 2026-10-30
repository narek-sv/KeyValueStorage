//
//  KeychainIntegrationTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import XCTest
import Foundation
import Security
import KeyValueStorage // not @testable: the real keychain through the public API

/// The default backing store and locator against the real keychain. Only an app can have keychain entitlements,
/// so these tests run in KeychainHost, whose access groups are its default one and `yyy.xxx`.
final class KeychainIntegrationTests: XCTestCase {
    private let defaultGroup = "ABCDE12345.com.github.narek-sv.KeychainHost"
    private let sharedGroup = "yyy.xxx"
    private var tag: String!

    override func setUp() {
        tag = "KeychainIntegrationTests-\(UUID().uuidString)"
    }

    override func tearDown() {
        // Every item a test made has this tag as its account or in its service
        for service in services() where service.contains(tag) {
            SecItemDelete(query([kSecAttrService: service, kSecAttrSynchronizable: kSecAttrSynchronizableAny]))
        }

        SecItemDelete(query([kSecAttrAccount: tag!, kSecAttrSynchronizable: kSecAttrSynchronizableAny]))
    }

    // MARK: Values

    func testValuesRoundTripAndPersistAcrossInstances() throws {
        // When
        try storage(.own(namespace: namespace())).save(Data([1]), forKey: "key")
        try storage(.own(namespace: namespace())).save(Data(), forKey: "empty")

        // Then
        XCTAssertEqual(try storage(.own(namespace: namespace())).fetch(forKey: "key"), Data([1]))
        XCTAssertEqual(try storage(.own(namespace: namespace())).fetch(forKey: "empty"), Data())
    }

    func testKeysAreTheirExactBytes() throws {
        // Given
        let storage = storage(.own(namespace: namespace()))

        // When
        try storage.save(Data([1]), forKey: "\u{E9}")
        try storage.save(Data([2]), forKey: "e\u{301}")

        // Then: two items, as in every storage
        XCTAssertEqual(try storage.fetch(forKey: "\u{E9}"), Data([1]))
        XCTAssertEqual(try storage.fetch(forKey: "e\u{301}"), Data([2]))
    }

    // MARK: Protection

    func testTheScopesProtectionIsTheItemsAccessibility() throws {
        let scopes: [(KeychainStorage.Scope, CFString)] = [
            (.own(protection: .untilFirstUnlock, namespace: namespace()), kSecAttrAccessibleAfterFirstUnlock),
            (.own(protection: .whileLockedThisDeviceOnly, namespace: namespace()), kSecAttrAccessibleWhenUnlockedThisDeviceOnly),
            (.own(namespace: namespace()), kSecAttrAccessibleWhenUnlocked),
            (.iCloud(.own, protection: .untilFirstUnlock, namespace: namespace()), kSecAttrAccessibleAfterFirstUnlock)
        ]

        for (scope, accessibility) in scopes {
            // When
            try storage(scope).save(Data([1]), forKey: "key")

            // Then
            XCTAssertEqual(try attribute(kSecAttrAccessible, of: scope, account: "key") as? String, accessibility as String, "\(scope)")
        }
    }

    func testScopesThatDifferOnlyInProtectionNeverShareItems() throws {
        // Given
        let firstUnlock = storage(.own(protection: .untilFirstUnlock, namespace: namespace()))
        let unlocked = storage(.own(protection: .whileLocked, namespace: namespace()))

        // When
        try firstUnlock.save(Data([1]), forKey: "key")
        try unlocked.save(Data([2]), forKey: "key")
        try unlocked.clear()

        // Then
        XCTAssertEqual(try firstUnlock.fetch(forKey: "key"), Data([1]))
        XCTAssertNil(try unlocked.fetch(forKey: "key"))
    }

    // MARK: Scopes

    func testSyncedScopesNeverReachTheLocalItemsOfTheirService() throws {
        // Given: one service, told apart by sync alone
        let local = storage(.own(namespace: namespace()))
        let synced = storage(.iCloud(.own, namespace: namespace()))

        // When
        try synced.save(Data([1]), forKey: "key")
        try local.save(Data([2]), forKey: "key")

        // Then
        XCTAssertEqual(try synced.fetch(forKey: "key"), Data([1]))
        XCTAssertEqual(try local.fetch(forKey: "key"), Data([2]))
        XCTAssertEqual(try attribute(kSecAttrSynchronizable, of: .iCloud(.own, namespace: namespace()), account: "key") as? Bool, true)

        // When
        try local.clear()

        // Then
        XCTAssertEqual(try synced.fetch(forKey: "key"), Data([1]))
        XCTAssertNil(try local.fetch(forKey: "key"))

        // When
        try synced.clear()

        // Then
        XCTAssertNil(try synced.fetch(forKey: "key"))
    }

    func testOwnScopesAndAppGroupsNeverReachEachOthersItems() throws {
        // Given: an own scope, whose queries reach every access group, and App Groups with the same namespace,
        // one of them the app's default group, where the own scope's items go
        let scopes: [KeychainStorage.Scope] = [
            .own(namespace: namespace()),
            .appGroup(id: sharedGroup, namespace: namespace()),
            .appGroup(id: defaultGroup, namespace: namespace()),
            .iCloud(.own, namespace: namespace()),
            .iCloud(.appGroup(id: sharedGroup), namespace: namespace())
        ]
        let storages = scopes.map(storage)

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
        for (index, storage) in storages.enumerated().dropFirst() {
            XCTAssertEqual(try storage.fetch(forKey: "token"), Data([UInt8(index)]), "\(scopes[index])")
        }
    }

    func testAGroupTheAppIsntEntitledToIsReported() {
        assertKeychainError(errSecMissingEntitlement) {
            try self.storage(.appGroup(id: "not.entitled", namespace: self.namespace())).save(Data([1]), forKey: "key")
        }
    }

    func testAnEmptyGroupIdIsReported() {
        for scope in [KeychainStorage.Scope.appGroup(id: "", namespace: namespace()), .iCloud(.appGroup(id: ""), namespace: namespace())] {
            assertKeychainError(errSecMissingEntitlement) { try self.storage(scope).save(Data([1]), forKey: "key") }
        }
    }

    // MARK: Other Code's Items

    func testAnItemWithoutDataFetchesAsNilAndIsReplacedAndRemovedLikeAValue() throws {
        // Given: items without data at two of the scope's accounts
        let scope = KeychainStorage.Scope.own(namespace: namespace())
        let storage = storage(scope)
        for account in ["key", "other"] {
            XCTAssertEqual(SecItemAdd(query([kSecAttrService: service(of: scope), kSecAttrAccount: account]), nil), errSecSuccess)
        }

        // When - Then
        XCTAssertNil(try storage.fetch(forKey: "key"))

        try storage.save(Data([1]), forKey: "key")
        XCTAssertEqual(try storage.fetch(forKey: "key"), Data([1]))

        try storage.delete(forKey: "key")
        XCTAssertEqual(SecItemCopyMatching(query([kSecAttrService: service(of: scope), kSecAttrAccount: "key"]), nil), errSecItemNotFound)

        try storage.clear()
        XCTAssertEqual(SecItemCopyMatching(query([kSecAttrService: service(of: scope), kSecAttrAccount: "other"]), nil), errSecItemNotFound)
    }

    func testOtherCodesItemsAreNeverReached() throws {
        // Given: items without a service, and with the namespace as their service
        for service in [nil, tag] {
            var attributes: [CFString: Any] = [kSecAttrAccount: tag!, kSecValueData: Data([1])]
            attributes[kSecAttrService] = service
            XCTAssertEqual(SecItemAdd(query(attributes), nil), errSecSuccess)
        }

        let storage = storage(.own(namespace: namespace()))

        // When
        let fetched = try storage.fetch(forKey: .init(tag))
        try storage.clear()

        // Then
        var result: AnyObject?
        XCTAssertNil(fetched)
        XCTAssertEqual(SecItemCopyMatching(query([kSecAttrAccount: tag!, kSecMatchLimit: kSecMatchLimitAll, kSecReturnAttributes: true]), &result), errSecSuccess)
        XCTAssertEqual((result as? [[String: Any]])?.count, 2)
    }

    // MARK: Helpers

    private func storage(_ scope: KeychainStorage.Scope) -> KeychainStorage {
        KeychainStorage(scope: scope, backingStore: DefaultKeychainBackingStoreWrapper(), locator: DefaultKeychainLocator())
    }

    private func namespace() -> KeychainStorage.Namespace {
        .init(tag)
    }

    private func service(of scope: KeychainStorage.Scope) -> String {
        DefaultKeychainLocator().service(for: scope)
    }

    private func query(_ attributes: [CFString: Any]) -> CFDictionary {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecUseDataProtectionKeychain as String: true]
        for (key, value) in attributes {
            query[key as String] = value
        }

        return query as CFDictionary
    }

    private func attribute(_ attribute: CFString, of scope: KeychainStorage.Scope, account: String) throws -> Any? {
        // The scope's kind of item: a synced and a local item can share a service and account
        var synchronizable = false
        if case .iCloud = scope {
            synchronizable = true
        }

        var result: AnyObject?
        let attributes: [CFString: Any] = [kSecAttrService: service(of: scope), kSecAttrAccount: account, kSecReturnAttributes: true, kSecAttrSynchronizable: synchronizable]
        let status = SecItemCopyMatching(query(attributes), &result)
        XCTAssertEqual(status, errSecSuccess)
        return (result as? [String: Any])?[attribute as String]
    }

    /// Every service of the app's generic passwords.
    private func services() -> [String] {
        var result: AnyObject?
        let status = SecItemCopyMatching(query([kSecMatchLimit: kSecMatchLimitAll, kSecReturnAttributes: true, kSecAttrSynchronizable: kSecAttrSynchronizableAny]), &result)
        return status == errSecSuccess ? (result as? [[String: Any]] ?? []).compactMap { $0[kSecAttrService as String] as? String } : []
    }

    private func assertKeychainError(_ expected: OSStatus, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard case .keychain(status: expected)? = error as? KeychainStorage.Error else {
                return XCTFail("Expected .keychain(status: \(expected)), got \(error)", file: file, line: line)
            }
        }
    }
}
