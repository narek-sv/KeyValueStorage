//
//  KeyValueDataStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - KeyValueDataStorage

/// - Warning: Synchronous and unsynchronized: use an instance from one thread or actor.
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
    /// Every `default` scope's suite, directory, service, key prefix or bucket.
    static var defaultName: String {
        "KeyValueStorage"
    }
}

// MARK: - Associated Type Requirements

public typealias KeyValueDataStorageKey = Hashable & Sendable
public typealias KeyValueDataStorageError = Error & Sendable
public typealias KeyValueDataStorageNamespace = Hashable & Sendable
/// Cases default to a `nil` namespace; `default` uses the package's.
public protocol KeyValueDataStorageScope: Hashable & Sendable {
    associatedtype Namespace: KeyValueDataStorageNamespace

    var namespace: Namespace? { get }
    static var `default`: Self { get }
}
