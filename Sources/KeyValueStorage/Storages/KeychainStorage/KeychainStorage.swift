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
    private let accessibility: KeychainQuery.Accessibility
    private let synchronizable: KeychainQuery.Synchronizable

    public let scope: Scope

    // MARK: Initializers

    public init(scope: Scope, backingStore: any KeychainBackingStore, locator: any KeychainLocator) {
        self.service = locator.service(for: scope)
        self.accessGroup = locator.accessGroup(for: scope)
        self.accessibility = Self.accessibility(for: scope)
        self.synchronizable = Self.synchronizable(for: scope)
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
        let (status, result) = backingStore.read(query(account: account(for: key), returnData: true, matchLimit: .one))
        switch status {
        case .success:  return result as? Data
        case .notFound: return nil
        default:        throw Error(status)
        }
    }

    public func save(_ value: Data, forKey key: Key) throws(Error) {
        let account = account(for: key)
        let status = backingStore.update(query(account: account), with: KeychainQuery(accessibility: accessibility, valueData: value))
        guard status == .notFound else {
            return try check(status)
        }

        try check(backingStore.add(query(account: account, accessibility: accessibility, valueData: value)))
    }

    public func delete(forKey key: Key) throws(Error) {
        try removeValue(matching: query(account: account(for: key)))
    }

    public func clear() throws(Error) {
        try removeValue(matching: query(account: nil))
    }

    // MARK: Helpers

    private func removeValue(matching query: KeychainQuery) throws(Error) {
        let status = backingStore.remove(query)
        guard status != .notFound else {
            return
        }

        try check(status)
    }

    private func check(_ status: KeychainOperationStatus) throws(Error) {
        guard status == .success else {
            throw Error(status)
        }
    }

    private func account(for key: Key) -> String {
        locator.account(forKey: key, in: scope)
    }

    private func query(
        account: String?,
        accessibility: KeychainQuery.Accessibility? = nil,
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

    private static func accessibility(for scope: Scope) -> KeychainQuery.Accessibility {
        switch scope {
        case let .own(protection, _), let .appGroup(_, protection, _):
            switch protection {
            case .untilFirstUnlock:                 return .afterFirstUnlock
            case .untilFirstUnlockThisDeviceOnly:   return .afterFirstUnlockThisDeviceOnly
            case .whileLocked:                      return .whenUnlocked
            case .whileLockedThisDeviceOnly:        return .whenUnlockedThisDeviceOnly
            case .whileLockedOrWithoutPasscode:     return .whenPasscodeSetThisDeviceOnly
            }
        case let .iCloud(_, protection, _):
            switch protection {
            case .untilFirstUnlock:                 return .afterFirstUnlock
            case .whileLocked:                      return .whenUnlocked
            }
        }
    }

    private static func synchronizable(for scope: Scope) -> KeychainQuery.Synchronizable {
        switch scope {
        case .own, .appGroup:   return .no
        case .iCloud:           return .yes
        }
    }
}
