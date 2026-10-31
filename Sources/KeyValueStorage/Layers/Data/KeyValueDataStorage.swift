//
//  KeyValueDataStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - KeyValueDataStorage

/// A storage whose operations never suspend, so code that uses it directly never needs `await`.
/// - Note: Its `init(scope:)` is synchronous too, but isn't redeclared here: Swift 6.3 crashes compiling generic calls
///   to a synchronous init that redeclares an `async` one.
/// - Note: Thread safety isn't required: it's the storage's own concern until it's used in `UnifiedStorage`, which takes only
///   `Sendable` storages. The built-in storages are thread-safe; `IsolatedKeyValueDataStorage` makes any other one shareable.
public protocol KeyValueDataStorage: AsyncKeyValueDataStorage {
    func fetch(forKey key: Key) throws(Error) -> Data?
    func save(_ value: Data, forKey key: Key) throws(Error)
    func delete(forKey key: Key) throws(Error)
    func clear() throws(Error)
}

// MARK: - KeyValueDataStorage + Defaults

public extension KeyValueDataStorage {
    /// Saves `value`, or deletes it if `nil`.
    func set(_ value: Data?, forKey key: Key) throws(Error) {
        if let value {
            try save(value, forKey: key)
        } else {
            try delete(forKey: key)
        }
    }
}
