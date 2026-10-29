//
//  BackingStoreMocks.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import Foundation
import Security
import KeyValueStorage // intentionally not @testable: the backing storage protocols must be implementable by clients

/// Keeps items in memory, because the real keychain needs entitlements that test bundles can't have.
/// Items are identified like in the keychain: by service, account, access group and whether they're synchronizable.
final class InMemoryKeychain: KeychainBackingStore {
    private struct Item {
        let service: String?
        let accessGroup: String?
        let account: String?
        let synchronizable: Bool
        var data: Data?
    }

    private var items = [Item]()

    func add(_ attributes: KeychainQuery) -> KeychainOperationStatus {
        guard !items.contains(where: { matches($0, attributes) }) else {
            return .duplicate
        }

        items.append(Item(service: attributes.service, accessGroup: attributes.accessGroup, account: attributes.account,
                          synchronizable: attributes.synchronizable == .yes, data: attributes.valueData))
        return .success
    }

    func read(_ query: KeychainQuery) -> (KeychainOperationStatus, AnyObject?) {
        let matching = items.filter { matches($0, query) }
        guard let first = matching.first else {
            return (.notFound, nil)
        }

        guard query.matchLimit == .all else {
            return (.success, first.data as NSData?)
        }

        // What `clear()` lists: each item's account, synchronizability and data
        return (.success, matching.map { item -> [String: Any] in
            var attributes: [String: Any] = [kSecAttrAccount as String: item.account ?? "", kSecAttrSynchronizable as String: item.synchronizable]
            attributes[kSecValueData as String] = item.data
            return attributes
        } as NSArray)
    }

    func update(_ query: KeychainQuery, with attributes: KeychainQuery) -> KeychainOperationStatus {
        let indices = items.indices.filter { matches(items[$0], query) }
        indices.forEach { items[$0].data = attributes.valueData }
        return indices.isEmpty ? .notFound : .success
    }

    func remove(_ query: KeychainQuery) -> KeychainOperationStatus {
        let count = items.count
        items.removeAll { matches($0, query) }
        return items.count == count ? .notFound : .success
    }

    private func matches(_ item: Item, _ query: KeychainQuery) -> Bool {
        item.service == query.service && item.accessGroup == query.accessGroup
            && (query.account == nil || item.account == query.account)
            && (query.synchronizable == .any || item.synchronizable == (query.synchronizable == .yes))
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
