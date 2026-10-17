//
//  KeychainStorage.swift
//
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - KeychainStorage

public final class KeychainStorage: KeyValueDataStorage {

    // MARK: Properties

    private let storage: any KeychainBackingStore
    private let serviceName: String?
    private let accessGroup: String?

    public let domain: Domain

    // MARK: Initializers

    public init(domain: Domain, backingStorage: any KeychainBackingStore) {
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

    public convenience init(domain: Domain) {
        self.init(domain: domain, backingStorage: DefaultKeychainBackingStoreWrapper())
    }

    public convenience init() {
        self.init(domain: .default)
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) throws -> Data? {
        let (status, result) = storage.read(query(for: key, returnData: true, matchLimit: .one))
        switch status {
        case .success:
            guard let data = result as? Data else {
                throw Error.decodedWrongType
            }

            return data
        case .notFound:
            return nil
        default:
            throw Error.os(status.code)
        }
    }

    public func save(_ value: Data, forKey key: Key) throws {
        let addStatus = storage.add(query(for: key, accessibility: key.accessibility, valueData: value))
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

        let updateStatus = storage.update(query(for: key), with: updateAttributes)
        guard updateStatus != .success else {
            return
        }

        throw Error.os(updateStatus.code)
    }

    public func delete(forKey key: Key) throws {
        let status = storage.remove(query(for: key))
        guard status != .success && status != .notFound else {
            return
        }

        throw Error.os(status.code)
    }

    public func clear() throws {
        let status = storage.remove(query(account: nil, synchronizable: .any))
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
            account: key.name,
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
