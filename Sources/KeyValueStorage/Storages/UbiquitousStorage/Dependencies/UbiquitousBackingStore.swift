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

/// The live iCloud key-value store.
@available(watchOS 9.0, *)
open class DefaultUbiquitousBackingStoreWrapper: UbiquitousBackingStore {
    private var store: NSUbiquitousKeyValueStore { .default }

    public init() { }

    open func read(forKey key: String) -> Data? {
        store.data(forKey: key)
    }

    open func write(_ data: Data, forKey key: String) {
        store.set(data, forKey: key)
    }

    open func remove(forKey key: String) {
        store.removeObject(forKey: key)
    }

    open func keys() -> [String] {
        Array(store.dictionaryRepresentation.keys)
    }

    open func synchronize() -> Bool {
        store.synchronize()
    }
}
