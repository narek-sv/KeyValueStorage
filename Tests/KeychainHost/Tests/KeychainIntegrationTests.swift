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
        try storage(.app(namespace: namespace())).save(Data([1]), forKey: "key")
        try storage(.app(namespace: namespace())).save(Data(), forKey: "empty")

        // Then
        XCTAssertEqual(try storage(.app(namespace: namespace())).fetch(forKey: "key"), Data([1]))
        XCTAssertEqual(try storage(.app(namespace: namespace())).fetch(forKey: "empty"), Data())
    }

    func testAccessibilityIsSetOnAddAndOnUpdate() throws {
        // Given
        let storage = storage(.app(namespace: namespace()))

        // When - Then
        try storage.save(Data([1]), forKey: .init(name: "key", accessibility: .afterFirstUnlock))
        XCTAssertEqual(try attribute(kSecAttrAccessible, service: tag, account: "key") as? String, kSecAttrAccessibleAfterFirstUnlock as String)

        try storage.save(Data([2]), forKey: .init(name: "key", accessibility: .whenUnlockedThisDeviceOnly))
        XCTAssertEqual(try attribute(kSecAttrAccessible, service: tag, account: "key") as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(try storage.fetch(forKey: "key"), Data([2]))
    }

    func testKeysAreTheirExactBytes() throws {
        // Given
        let storage = storage(.app(namespace: namespace()))

        // When
        try storage.save(Data([1]), forKey: "\u{E9}")
        try storage.save(Data([2]), forKey: "e\u{301}")

        // Then: two items, as in every storage
        XCTAssertEqual(try storage.fetch(forKey: "\u{E9}"), Data([1]))
        XCTAssertEqual(try storage.fetch(forKey: "e\u{301}"), Data([2]))
    }

    func testSynchronizableKeysAreItemsOfTheirOwn() throws {
        // Given
        let storage = storage(.app(namespace: namespace()))

        // When
        try storage.save(Data([1]), forKey: .init(name: "key", isSynchronizable: true))
        try storage.save(Data([2]), forKey: "key")

        // Then
        XCTAssertEqual(try storage.fetch(forKey: .init(name: "key", isSynchronizable: true)), Data([1]))
        XCTAssertEqual(try storage.fetch(forKey: "key"), Data([2]))

        // When
        try storage.clear()

        // Then
        XCTAssertNil(try storage.fetch(forKey: .init(name: "key", isSynchronizable: true)))
        XCTAssertNil(try storage.fetch(forKey: "key"))
    }

    // MARK: Scopes

    func testTheRootNeverReachesNamespacedItems() throws {
        // Given
        let root = storage(.app())
        let namespaced = storage(.app(namespace: namespace()))
        try root.save(Data([1]), forKey: .init(name: tag))
        try namespaced.save(Data([2]), forKey: .init(name: tag))

        // When
        try root.clear()

        // Then
        XCTAssertNil(try root.fetch(forKey: .init(name: tag)))
        XCTAssertEqual(try namespaced.fetch(forKey: .init(name: tag)), Data([2]))
    }

    func testAppScopesAndAppGroupsNeverReachEachOthersItems() throws {
        // Given: an app scope, whose queries reach every access group, and App Groups with the same namespace,
        // one of them the app's default group, where the app scope's items go
        let scopes: [KeychainStorage.Scope] = [
            .app(namespace: namespace()),
            .appGroup(groupId: sharedGroup, namespace: namespace()),
            .appGroup(groupId: defaultGroup, namespace: namespace())
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
        XCTAssertEqual(try storages[1].fetch(forKey: "token"), Data([1]))
        XCTAssertEqual(try storages[2].fetch(forKey: "token"), Data([2]))
    }

    func testAGroupTheAppIsntEntitledToIsReported() {
        assertOSError(errSecMissingEntitlement) {
            try self.storage(.appGroup(groupId: "not.entitled", namespace: self.namespace())).save(Data([1]), forKey: "key")
        }
    }

    // MARK: Other Code's Items

    func testAnItemWithoutDataIsNeverAValueAndNeverReplacedOrRemoved() throws {
        // Given: another app's item, at a key's service and account, without data
        let storage = storage(.app(namespace: namespace()))
        XCTAssertEqual(SecItemAdd(query([kSecAttrService: tag!, kSecAttrAccount: "key"]), nil), errSecSuccess)

        // When
        let fetched = try storage.fetch(forKey: "key")
        try storage.delete(forKey: "key")
        try storage.clear()

        // Then
        XCTAssertNil(fetched)
        XCTAssertThrowsError(try storage.save(Data([1]), forKey: "key")) { error in
            guard case .keyOccupied("key")? = error as? KeychainStorage.Error else {
                return XCTFail("Unexpected \(error)")
            }
        }

        XCTAssertEqual(SecItemCopyMatching(query([kSecAttrService: tag!, kSecAttrAccount: "key"]), nil), errSecSuccess)
    }

    func testItemsWithoutAServiceShareTheRoot() throws {
        // Given: the documented edge, another app's item saved without a service
        XCTAssertEqual(SecItemAdd(query([kSecAttrAccount: tag!, kSecValueData: Data([1])]), nil), errSecSuccess)

        // When - Then
        XCTAssertEqual(try storage(.app()).fetch(forKey: .init(name: tag)), Data([1]))
    }

    // MARK: Helpers

    private func storage(_ scope: KeychainStorage.Scope) -> KeychainStorage {
        KeychainStorage(scope: scope, backingStore: DefaultKeychainBackingStoreWrapper(), locator: DefaultKeychainLocator())
    }

    private func namespace() -> KeychainStorage.Namespace {
        .service(named: tag)
    }

    private func query(_ attributes: [CFString: Any]) -> CFDictionary {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecUseDataProtectionKeychain as String: true]
        for (key, value) in attributes {
            query[key as String] = value
        }

        return query as CFDictionary
    }

    private func attribute(_ attribute: CFString, service: String, account: String) throws -> Any? {
        var result: AnyObject?
        let status = SecItemCopyMatching(query([kSecAttrService: service, kSecAttrAccount: account, kSecReturnAttributes: true]), &result)
        XCTAssertEqual(status, errSecSuccess)
        return (result as? [String: Any])?[attribute as String]
    }

    /// Every service of the app's generic passwords.
    private func services() -> [String] {
        var result: AnyObject?
        let status = SecItemCopyMatching(query([kSecMatchLimit: kSecMatchLimitAll, kSecReturnAttributes: true, kSecAttrSynchronizable: kSecAttrSynchronizableAny]), &result)
        return status == errSecSuccess ? (result as? [[String: Any]] ?? []).compactMap { $0[kSecAttrService as String] as? String } : []
    }

    private func assertOSError(_ expected: OSStatus, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard case .os(expected)? = error as? KeychainStorage.Error else {
                return XCTFail("Expected .os(\(expected)), got \(error)", file: file, line: line)
            }
        }
    }
}
