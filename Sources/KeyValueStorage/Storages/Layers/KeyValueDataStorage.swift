//
//  KeyValueDataStorage.swift
//  
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - Data Storage Protocol

public protocol KeyValueDataStorage: Sendable {
    associatedtype Key: KeyValueDataStorageKey
    associatedtype Domain: KeyValueDataStorageDomain
    associatedtype Error: KeyValueDataStorageError
    
    var domain: Domain { get }

    init() async throws
    init(domain: Domain) async throws
    
    func fetch(forKey key: Key) async throws -> Data?
    func save(_ value: Data, forKey key: Key) async throws
    func set(_ value: Data?, forKey key: Key) async throws
    func delete(forKey key: Key) async throws
    func clear() async throws
}

// MARK: - Default Implementations

public extension KeyValueDataStorageDomain {
    /// The package-owned container name used when a caller doesn't choose a domain explicitly.
    ///
    /// A dedicated name is intentional: default operations, especially `clear()`, stay in `KeyValueStorage`'s
    /// namespace instead of reading or removing values from the app's standard storage or containers owned by other SDKs.
    /// Individual storages resolve this logical name to their own suite, service, directory or namespace.
    static var defaultContainerName: String {
        "KeyValueStorage"
    }
}

// MARK: - Associated Type Requirements

public typealias KeyValueDataStorageKey = Hashable & Sendable
public typealias KeyValueDataStorageError = Error & Sendable
public typealias KeyValueDataStorageAppDomain = Hashable & Sendable
public protocol KeyValueDataStorageDomain: Hashable & Sendable {
    static var `default`: Self { get }
}

