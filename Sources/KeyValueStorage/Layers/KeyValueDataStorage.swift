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
    /// Every `default` scope's namespace.
    /// - Warning: Shared by everything in the app that uses a `default` scope.
    static var defaultNamespace: ExactString {
        "KeyValueStorage"
    }

    /// Every `default` scope's suite, directory, service, key prefix or bucket.
    static var defaultName: String {
        "KeyValueStorage"
    }
}

// MARK: - Associated Type Requirements

public typealias KeyValueDataStorageKey = Hashable & Sendable
public typealias KeyValueDataStorageError = Error & Sendable
public typealias KeyValueDataStorageNamespace = Hashable & Sendable
/// - Warning: `.own` belongs to the bundle ID: builds that share one share values, and unit tests hosted in an app use the app's,
///   so a test's `clear()` empties the app's data on that device. Give tests a namespace of their own.
public protocol KeyValueDataStorageScope: Hashable & Sendable {
    static var `default`: Self { get }
}
