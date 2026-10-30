//
//  KeychainStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation
import Security

// MARK: - KeychainStorage

/// Values in generic password items, one per key, in the scope's service and access group.
/// - Note: `save`, `delete` and `clear()` never read an item first: reading decrypts it, which fails while the device is locked.
///   An item without data fetches as `nil`, and is replaced and removed like any value.
/// - Warning: If another process adds the key's item between `save`'s update and its add, the add's error is thrown.
public final class KeychainStorage: KeyValueDataStorage {

    // MARK: Properties

    private let backingStore: any KeychainBackingStore
    private let locator: any KeychainLocator
    private let service: String
    private let accessGroup: String?

    public let scope: Scope

    // MARK: Initializers

    public init(scope: Scope, backingStore: any KeychainBackingStore, locator: any KeychainLocator) {
        self.service = locator.service(for: scope)
        self.accessGroup = locator.accessGroup(for: scope)
        self.scope = scope
        self.backingStore = backingStore
        self.locator = locator
    }

    public convenience init(scope: Scope) {
        self.init(scope: scope, backingStore: DefaultKeychainBackingStoreWrapper(), locator: DefaultKeychainLocator())
    }

    public convenience init() {
        self.init(scope: .default)
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) throws(Error) -> Data? {
        let (status, result) = backingStore.read(query(for: key, returnData: true, matchLimit: .one))
        switch status {
        case .success:  return result as? Data
        case .notFound: return nil
        default:        throw .os(status.code)
        }
    }

    public func save(_ value: Data, forKey key: Key) throws(Error) {
        let status = backingStore.update(query(for: key), with: KeychainQuery(accessibility: key.accessibility, valueData: value))
        guard status == .notFound else {
            return try check(status)
        }

        try check(backingStore.add(query(for: key, accessibility: key.accessibility, valueData: value)))
    }

    public func delete(forKey key: Key) throws(Error) {
        try remove(query(for: key))
    }

    public func clear() throws(Error) {
        try remove(query(account: nil, synchronizable: .any))
    }

    // MARK: Helpers

    private func remove(_ query: KeychainQuery) throws(Error) {
        let status = backingStore.remove(query)
        guard status != .notFound else {
            return
        }

        try check(status)
    }

    private func check(_ status: KeychainOperationStatus) throws(Error) {
        guard status == .success else {
            throw .os(status.code)
        }
    }

    private func account(for key: Key) -> String {
        locator.account(forKey: key.name, in: scope)
    }

    private func query(
        for key: Key,
        accessibility: Key.Accessibility? = nil,
        returnData: Bool? = nil,
        matchLimit: KeychainQuery.MatchLimit? = nil,
        valueData: Data? = nil
    ) -> KeychainQuery {
        query(
            account: account(for: key),
            synchronizable: key.isSynchronizable ? .yes : .no,
            accessibility: accessibility,
            returnData: returnData,
            matchLimit: matchLimit,
            valueData: valueData
        )
    }

    private func query(
        account: String?,
        synchronizable: KeychainQuery.Synchronizable,
        accessibility: Key.Accessibility? = nil,
        returnData: Bool? = nil,
        matchLimit: KeychainQuery.MatchLimit? = nil,
        valueData: Data? = nil
    ) -> KeychainQuery {
        KeychainQuery(
            itemClass: .genericPassword,
            service: service,
            account: account,
            accessGroup: accessGroup,
            synchronizable: synchronizable,
            accessibility: accessibility,
            useDataProtectionKeychain: true,
            returnData: returnData,
            matchLimit: matchLimit,
            valueData: valueData
        )
    }
}
