//
//  UbiquitousBackingStore.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import Foundation

// MARK: - UbiquitousBackingStore

public protocol UbiquitousBackingStore {
    func read(forKey key: String) -> Data?
    func write(_ data: Data, forKey key: String)
    func remove(forKey key: String)
    func keys() -> [String]
    func synchronize() -> Bool
}

// MARK: - DefaultUbiquitousBackingStoreWrapper

@available(watchOS 9.0, *)
final class DefaultUbiquitousBackingStoreWrapper: UbiquitousBackingStore {
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
