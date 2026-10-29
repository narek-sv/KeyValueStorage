//
//  BackingStoreMocks.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import Foundation
import KeyValueStorage // intentionally not @testable: the backing storage protocols must be implementable by clients

/// Keeps items in memory, because the real keychain needs entitlements that test bundles can't have.
/// Items are identified like in the keychain: by service, account, access group and whether they're synchronizable.
final class InMemoryKeychain: KeychainBackingStore {
    private var items = [String: Data]()

    func add(_ attributes: KeychainQuery) -> KeychainOperationStatus {
        let id = identity(of: attributes)
        guard items[id] == nil else {
            return .duplicate
        }

        items[id] = attributes.valueData
        return .success
    }

    func read(_ query: KeychainQuery) -> (KeychainOperationStatus, AnyObject?) {
        guard let data = items[identity(of: query)] else {
            return (.notFound, nil)
        }

        return (.success, data as NSData)
    }

    func update(_ query: KeychainQuery, with attributes: KeychainQuery) -> KeychainOperationStatus {
        let id = identity(of: query)
        guard items[id] != nil else {
            return .notFound
        }

        items[id] = attributes.valueData
        return .success
    }

    func remove(_ query: KeychainQuery) -> KeychainOperationStatus {
        // A query without an account matches every item of the service and access group, like `clear()` sends
        let matching = query.account == nil
            ? items.keys.filter { $0.hasPrefix(scope(of: query)) }
            : items.keys.filter { $0 == identity(of: query) }

        matching.forEach { items[$0] = nil }
        return matching.isEmpty ? .notFound : .success
    }

    private func scope(of query: KeychainQuery) -> String {
        "\(query.service ?? "")|\(query.accessGroup ?? "")|"
    }

    private func identity(of query: KeychainQuery) -> String {
        scope(of: query) + "\(query.account ?? "")|\(query.synchronizable == .yes)"
    }
}

/// Keeps values in memory, because the real iCloud key-value store needs an entitlement that test bundles can't have.
final class InMemoryUbiquitousStore: UbiquitousBackingStore {
    private var values = [String: Data]()

    func read(forKey key: String) -> Any? {
        values[key]
    }

    func write(_ data: Data, forKey key: String) {
        values[key] = data
    }

    func remove(forKey key: String) {
        values[key] = nil
    }

    func keys() -> [String] {
        Array(values.keys)
    }

    func synchronize() -> Bool {
        true
    }
}

/// Buckets of its own, unlike the default in-memory backing store, which the whole process shares.
final class IsolatedInMemoryStore: InMemoryBackingStore {
    private var buckets = [String?: [String: Data]]()

    func read(forKey key: String, in bucket: String?) -> Data? {
        buckets[bucket]?[key]
    }

    func write(_ data: Data, forKey key: String, in bucket: String?) {
        buckets[bucket, default: [:]][key] = data
    }

    func remove(forKey key: String, in bucket: String?) {
        buckets[bucket]?[key] = nil
    }

    func removeAll(in bucket: String?) {
        buckets[bucket] = nil
    }
}
