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

    static var defaultGroup: String { get }
    
    var domain: Domain? { get }

    init() async throws
    init(domain: Domain) async throws
    
    func fetch(forKey key: Key) async throws -> Data?
    func save(_ value: Data, forKey key: Key) async throws
    func set(_ value: Data?, forKey key: Key) async throws
    func delete(forKey key: Key) async throws
    func clear() async throws
}

// MARK: - Default Implementations

public extension KeyValueDataStorage {
    static var defaultGroup: String {
        Bundle.main.bundleIdentifier ?? "KeyValueDataStorage"
    }
}

// MARK: - Associated Type Requirements

public typealias KeyValueDataStorageKey = Hashable & Sendable
public typealias KeyValueDataStorageDomain = Hashable & Sendable
public typealias KeyValueDataStorageError = Error & Sendable
