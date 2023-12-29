//
//  KeyValueDataStorage.swift
//  
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

public protocol KeyValueDataStorageError: Error, Sendable {
    static func other(_ error: Error & Sendable) -> Self
}

public protocol KeyValueDataStorage: Sendable {
    associatedtype Key: KeyValueDataStorageKey
    associatedtype Domain: KeyValueDataStorageDomain
    associatedtype Error: KeyValueDataStorageError

    static var defaultGroup: String { get }

    init(domain: Domain?) throws
    
    func fetch(forKey key: Key) async throws -> Data?
    func save(_ value: Data, forKey key: Key) async throws
    func set(_ value: Data?, forKey key: Key) async throws
    func delete(forKey key: Key) async throws
    func clear() async throws
}

public extension KeyValueDataStorage {
    init() throws {
        try self.init(domain: nil)
    }
    
    static var defaultGroup: String {
        Bundle.main.bundleIdentifier ?? "KeyValueDataStorage"
    }
    
    func set(_ value: Data?, forKey key: Key) async throws {
        if let value = value {
            try await save(value, forKey: key)
        } else {
            try await delete(forKey: key)
        }
    }
}
