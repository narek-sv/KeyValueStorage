//
//  UbiquitousBackingStore.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import Foundation

// MARK: - UbiquitousBackingStore

public protocol UbiquitousBackingStore: Sendable {
    /// `NSUbiquitousKeyValueStore.object(forKey:)`.
    func read(forKey key: String) -> Any?
    /// `NSUbiquitousKeyValueStore.set(_:forKey:)`.
    func write(_ data: Data, forKey key: String)
    /// `NSUbiquitousKeyValueStore.removeObject(forKey:)`.
    func remove(forKey key: String)
    /// `NSUbiquitousKeyValueStore.dictionaryRepresentation.keys`.
    func keys() -> [String]
    /// `NSUbiquitousKeyValueStore.synchronize()`.
    func synchronize() -> Bool
}

// MARK: - DefaultUbiquitousBackingStoreWrapper

/// The live iCloud key-value store.
@available(watchOS 9.0, *)
/// - Warning: Subclasses inherit `Sendable`: their own state must be thread-safe too.
open class DefaultUbiquitousBackingStoreWrapper: UbiquitousBackingStore, @unchecked Sendable {
    private var store: NSUbiquitousKeyValueStore { .default }

    public init() { }

    open func read(forKey key: String) -> Any? {
        store.object(forKey: key)
    }

    open func write(_ data: Data, forKey key: String) {
        store.set(data, forKey: key)
    }

    open func remove(forKey key: String) {
        store.removeObject(forKey: key)
    }

    open func keys() -> [String] {
        // Through `NSDictionary`: a Swift dictionary merges keys that differ only in normalization, such as `"é"` and `"e\u{301}"`
        (store.dictionaryRepresentation as NSDictionary).allKeys.compactMap { $0 as? String }
    }

    open func synchronize() -> Bool {
        store.synchronize()
    }
}
