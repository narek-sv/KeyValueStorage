//
//  UbiquitousBackingStorage.swift
//  KeyValueStorage
//
//  Created by nsahakyan@servicetitan.com on 17.10.26.
//

import Foundation

// MARK: - UbiquitousBackingStorage

/// `NSUbiquitousKeyValueStore` calls of `UbiquitousStorage`, without validation.
public protocol UbiquitousBackingStorage {
    /// `NSUbiquitousKeyValueStore.data(forKey:)`.
    func read(forKey key: String) -> Data?

    /// `NSUbiquitousKeyValueStore.set(_:forKey:)`.
    func write(_ data: Data, forKey key: String)

    /// `NSUbiquitousKeyValueStore.removeObject(forKey:)`.
    func remove(forKey key: String)

    /// The keys of `NSUbiquitousKeyValueStore.dictionaryRepresentation`.
    func keys() -> [String]

    /// `NSUbiquitousKeyValueStore.synchronize()`.
    func synchronize() -> Bool
}

// MARK: - DefaultUbiquitousBackingStorage

/// The live `UbiquitousBackingStorage`.
@available(watchOS 9.0, *)
final class DefaultUbiquitousBackingStorage: UbiquitousBackingStorage {
    private var store: NSUbiquitousKeyValueStore { .default }

    func read(forKey key: String) -> Data? {
        store.data(forKey: key)
    }

    func write(_ data: Data, forKey key: String) {
        store.set(data, forKey: key)
    }

    func remove(forKey key: String) {
        store.removeObject(forKey: key)
    }

    func keys() -> [String] {
        Array(store.dictionaryRepresentation.keys)
    }

    func synchronize() -> Bool {
        store.synchronize()
    }
}
