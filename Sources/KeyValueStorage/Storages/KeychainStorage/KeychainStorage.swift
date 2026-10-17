//
//  KeychainStorage.swift
//
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - KeychainStorage

public final class KeychainStorage: KeyValueDataStorage {

    public static var defaultBackingStorage: any KeychainBackingStorage {
        DefaultKeychainBackingStorage()
    }

    // MARK: Properties

    private let storage: any KeychainBackingStorage
    private let serviceName: String?
    private let accessGroup: String?

    public let domain: Domain

    // MARK: Initializers

    /// Maps the domain to a service and an access group.
    public init(domain: Domain, backingStorage: any KeychainBackingStorage) {
        switch domain {
        case let .app(appContainer):
            self.serviceName = appContainer
            self.accessGroup = nil
        case let .appGroup(groupId, groupContainer):
            self.serviceName = groupContainer
            self.accessGroup = groupId
        }

        self.domain = domain
        self.storage = backingStorage
    }

    public convenience init(domain: Domain = .default) {
        self.init(domain: domain, backingStorage: Self.defaultBackingStorage)
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) throws -> Data? {
        let (status, result) = storage.read(query(for: key, returnData: true, matchLimit: .one))
        switch status {
        case .success, .notFound:
            return result as? Data
        default:
            throw Error.os(status.status)
        }
    }

    public func save(_ value: Data, forKey key: Key) throws {
        // Accessibility is set on add and update, so a change migrates on the next save
        let addStatus = storage.add(query(for: key, accessibility: key.accessibility, valueData: value))
        switch addStatus {
        case .success:
            return // ok
        case .duplicate:
            break // exists: update below
        default:
            throw Error.os(addStatus.status)
        }

        // SecItemUpdate takes item attributes only
        let updateAttributes = KeychainQuery(
            accessibility: key.accessibility,
            valueData: value
        )

        let updateStatus = storage.update(query(for: key), with: updateAttributes)
        guard updateStatus != .success else {
            return // ok
        }

        throw Error.os(updateStatus.status)
    }

    public func delete(forKey key: Key) throws {
        let status = storage.remove(query(for: key))
        guard status != .success && status != .notFound else {
            return // ok
        }

        throw Error.os(status.status)
    }

    public func clear() throws {
        // No account and any sync state: every item of the service
        let status = storage.remove(query(account: nil, synchronizable: .any))
        guard status != .success && status != .notFound else {
            return // ok
        }

        throw Error.os(status.status)
    }

    // MARK: Helpers

    /// A query for the item of `key`.
    private func query(
        for key: Key,
        accessibility: Key.Accessibility? = nil,
        returnData: Bool? = nil,
        matchLimit: KeychainQuery.MatchLimit? = nil,
        valueData: Data? = nil
    ) -> KeychainQuery {
        query(
            account: key.name,
            synchronizable: key.isSynchronizable ? .yes : .no,
            accessibility: accessibility,
            returnData: returnData,
            matchLimit: matchLimit,
            valueData: valueData
        )
    }

    /// A data protection keychain query in the domain's service and access group.
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
            service: serviceName,
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
