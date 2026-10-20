//
//  KeyValueDataStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - KeyValueDataStorage

/// Synchronous, unsynchronized raw-data storage: use an instance from one thread or actor.
/// It reaches the system only through its backing storage.
public protocol KeyValueDataStorage {
    associatedtype Key: KeyValueDataStorageKey
    associatedtype Scope: KeyValueDataStorageScope
    associatedtype Error: KeyValueDataStorageError
    
    var scope: Scope { get }
    
    init() throws(Error)
    init(scope: Scope) throws(Error)
    
    func fetch(forKey key: Key) throws(Error) -> Data?
    func save(_ value: Data, forKey key: Key) throws(Error)
    func delete(forKey key: Key) throws(Error)
    func clear() throws(Error)
}

// MARK: - KeyValueDataStorage + Defaults

public extension KeyValueDataStorage {
    init() throws(Error) {
        try self.init(scope: .default)
    }
    
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
    /// The package's name, used by every `default` scope as its suite, directory, service, key prefix or bucket.
    static var defaultName: String {
        "KeyValueStorage"
    }
}

// MARK: - Associated Type Requirements

/// Identifies a value within a scope.
public typealias KeyValueDataStorageKey = Hashable & Sendable
/// The errors a storage throws.
public typealias KeyValueDataStorageError = Error & Sendable
/// Separates sets of values within a scope, such as a directory, a keychain service or a key prefix.
public typealias KeyValueDataStorageNamespace = Hashable & Sendable
/// Where a storage keeps its values and who can read them. Cases default to a `nil` namespace; `default` uses the package's.
public protocol KeyValueDataStorageScope: Hashable & Sendable {
    /// The storage's way of separating values within the scope.
    associatedtype Namespace: KeyValueDataStorageNamespace

    var namespace: Namespace? { get }
    static var `default`: Self { get }
}
