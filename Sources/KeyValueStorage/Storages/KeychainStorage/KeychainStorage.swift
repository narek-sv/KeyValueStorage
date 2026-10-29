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
/// - Note: Only an item whose data is `Data` is a value. Any other item at a key's account is never fetched, updated
///   or removed, and `save` throws `.keyOccupied`.
/// - Warning: If another process changes an item between the storage's check and its call, the call's error is thrown.
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
        guard case let .value(data) = try item(forKey: key) else {
            return nil
        }

        return data
    }

    public func save(_ value: Data, forKey key: Key) throws(Error) {
        switch try item(forKey: key) {
        case .none:
            try check(backingStore.add(query(for: key, accessibility: key.accessibility, valueData: value)))
        case .value:
            try check(backingStore.update(query(for: key), with: KeychainQuery(accessibility: key.accessibility, valueData: value)))
        case .other:
            throw .keyOccupied(account(for: key))
        }
    }

    public func delete(forKey key: Key) throws(Error) {
        guard case .value = try item(forKey: key) else {
            return
        }

        try check(backingStore.remove(query(for: key)))
    }

    public func clear() throws(Error) {
        let (status, result) = backingStore.read(query(account: nil, synchronizable: .any, returnAttributes: true, returnData: true, matchLimit: .all))
        switch status {
        case .success:  break
        case .notFound: return
        default:        throw .os(status.code)
        }

        // One by one, because a query that matches the scope's items also matches the ones whose data isn't `Data`
        for item in result as? [[String: Any]] ?? [] where item[kSecValueData as String] is Data {
            guard let account = item[kSecAttrAccount as String] as? String else {
                continue
            }

            let synchronizable: KeychainQuery.Synchronizable = item[kSecAttrSynchronizable as String] as? Bool == true ? .yes : .no
            try check(backingStore.remove(query(account: account, synchronizable: synchronizable)))
        }
    }

    // MARK: Helpers

    private enum Item {
        case none
        case value(Data)
        case other
    }

    private func item(forKey key: Key) throws(Error) -> Item {
        let (status, result) = backingStore.read(query(for: key, returnData: true, matchLimit: .one))
        switch status {
        case .success:  return (result as? Data).map(Item.value) ?? .other
        case .notFound: return .none
        default:        throw .os(status.code)
        }
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
        returnAttributes: Bool? = nil,
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
            returnAttributes: returnAttributes,
            returnData: returnData,
            matchLimit: matchLimit,
            valueData: valueData
        )
    }
}
