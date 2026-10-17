//
//  KeyValueDataStorage.swift
//
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - KeyValueDataStorage

/// Synchronous, unsynchronized raw-data storage: use an instance from one thread or actor.
/// It reaches the system only through its backing storage.
public protocol KeyValueDataStorage {
    associatedtype Key: KeyValueDataStorageKey
    associatedtype Domain: KeyValueDataStorageDomain
    associatedtype Error: KeyValueDataStorageError
    
    var domain: Domain { get }
    
    init() throws
    init(domain: Domain) throws
    
    func fetch(forKey key: Key) throws -> Data?
    func save(_ value: Data, forKey key: Key) throws
    func delete(forKey key: Key) throws
    func clear() throws
}

// MARK: - KeyValueDataStorage + Defaults

public extension KeyValueDataStorage {
    init() throws {
        try self.init(domain: .default)
    }
    
    /// Saves `value`, or deletes it if `nil`.
    func set(_ value: Data?, forKey key: Key) throws {
        if let value {
            try save(value, forKey: key)
        } else {
            try delete(forKey: key)
        }
    }
}

// MARK: - KeyValueDataStorageDomain + Defaults

public extension KeyValueDataStorageDomain {
    /// The package-owned container of `default` domains, so `clear()` never touches other code's data.
    static var defaultContainerName: String {
        "KeyValueStorage"
    }
}

// MARK: - Associated Type Requirements

public typealias KeyValueDataStorageKey = Hashable & Sendable
public typealias KeyValueDataStorageError = Error & Sendable
public typealias KeyValueDataStorageContainer = Hashable & Sendable
public protocol KeyValueDataStorageDomain: Hashable & Sendable {
    static var `default`: Self { get }
}
