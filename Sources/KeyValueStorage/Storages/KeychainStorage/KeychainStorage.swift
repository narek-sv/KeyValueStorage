//
//  KeychainStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - KeychainStorage

public final class KeychainStorage: KeyValueDataStorage {

    // MARK: Properties

    private let backingStore: any KeychainBackingStore
    private let locator: any KeychainLocator
    private let service: String?
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
        case .success:
            guard let data = result as? Data else {
                throw Error.unexpectedItemData
            }

            return data
        case .notFound:
            return nil
        default:
            throw Error.os(status.code)
        }
    }

    public func save(_ value: Data, forKey key: Key) throws(Error) {
        let addStatus = backingStore.add(query(for: key, accessibility: key.accessibility, valueData: value))
        switch addStatus {
        case .success:
            return
        case .duplicate:
            break
        default:
            throw Error.os(addStatus.code)
        }

        let updateAttributes = KeychainQuery(
            accessibility: key.accessibility,
            valueData: value
        )

        let updateStatus = backingStore.update(query(for: key), with: updateAttributes)
        guard updateStatus != .success else {
            return
        }

        throw Error.os(updateStatus.code)
    }

    public func delete(forKey key: Key) throws(Error) {
        let status = backingStore.remove(query(for: key))
        guard status != .success && status != .notFound else {
            return
        }

        throw Error.os(status.code)
    }

    public func clear() throws(Error) {
        let status = backingStore.remove(query(account: nil, synchronizable: .any))
        guard status != .success && status != .notFound else {
            return
        }

        throw Error.os(status.code)
    }

    // MARK: Helpers

    private func query(
        for key: Key,
        accessibility: Key.Accessibility? = nil,
        returnData: Bool? = nil,
        matchLimit: KeychainQuery.MatchLimit? = nil,
        valueData: Data? = nil
    ) -> KeychainQuery {
        query(
            account: locator.account(forKey: key.name, in: scope),
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
