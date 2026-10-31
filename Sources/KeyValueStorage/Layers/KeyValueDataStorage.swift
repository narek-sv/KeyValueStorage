//
//  KeyValueDataStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - AsyncKeyValueDataStorage

/// A storage whose operations may suspend, such as one backed by a server.
/// - Note: Every `KeyValueDataStorage` is one too, with its synchronous methods.
/// - Note: No extension members: an `async` member here would win over a synchronous one of the same name inside `async` code,
///   so calls on synchronous storages would need `await`.
public protocol AsyncKeyValueDataStorage {
    associatedtype Key: Hashable & Sendable
    associatedtype Scope: KeyValueDataStorageScope
    associatedtype Error: Swift.Error & Sendable

    var scope: Scope { get }

    init(scope: Scope) async throws(Error)

    func fetch(forKey key: Key) async throws(Error) -> Data?
    func save(_ value: Data, forKey key: Key) async throws(Error)
    func delete(forKey key: Key) async throws(Error)
    func clear() async throws(Error)
}

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

// MARK: - KeyValueDataStorageScope + Defaults

public extension KeyValueDataStorageScope {
    /// Every `default` scope's namespace.
    /// - Warning: Shared by everything in the app that uses a `default` scope.
    static var defaultNamespace: ExactString {
        "KeyValueStorage"
    }
}

/// - Warning: `.own` belongs to the bundle ID: builds that share one share values, and unit tests hosted in an app use the app's,
///   so a test's `clear()` empties the app's data on that device. Give tests a namespace of their own.
public protocol KeyValueDataStorageScope: Hashable & Sendable {
    static var `default`: Self { get }
}
