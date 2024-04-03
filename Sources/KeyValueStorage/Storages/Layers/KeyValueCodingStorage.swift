//
//  KeyValueCodingStorage.swift
//  
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - Coding Storage Key

public struct KeyValueCodingStorageKey<Storage: KeyValueDataStorage, Value: CodingValue>: Sendable {
    public let key: Storage.Key
    public let codingType: Value.Type
    
    public init(key: Storage.Key) {
        self.key = key
        self.codingType = Value.self
    }
    
    internal init(key: Storage.Key, codingType: Value.Type) {
        self.key = key
        self.codingType = codingType
    }
}

extension KeyValueCodingStorageKey: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key &&
        lhs.codingType == rhs.codingType
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(String(describing: codingType))
    }
}

// MARK: - Coding Storage

@CodingStorageActor
open class KeyValueCodingStorage<Storage: KeyValueDataStorage>: @unchecked Sendable, Clearing {
    
    // MARK: Properties

    private let coder: DataCoder
    private let storage: Storage
    
    public var domain: Storage.Domain? {
        storage.domain
    }
    
    // MARK: Initializers
    
    public init(storage: Storage, coder: DataCoder = JSONDataCoder()) {
        self.coder = coder
        self.storage = storage
    }
    
    // MARK: Main Functionality
    
    public func fetch<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws -> Value? {
        if let data = try await storage.fetch(forKey: key.key) {
            return try await coder.decode(data)
        }
        
        return nil
    }
    
    public func save<Value: CodingValue>(_ value: Value, forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws {
        let encoded = try await coder.encode(value)
        try await storage.save(encoded, forKey: key.key)
    }
    
    public func set<Value: CodingValue>(_ value: Value?, forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws {
        if let value {
            try await save(value, forKey: key)
        } else {
            try await delete(forKey: key)
        }
    }
    
    public func delete<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws {
        try await storage.delete(forKey: key.key)
    }
    
    public func clear() async throws {
        try await storage.clear()
    }
}

// MARK: - Helper Protocols

protocol Clearing: Sendable {
    func clear() async throws
}

// MARK: - Global Actors

@globalActor
public final class CodingStorageActor {
    public actor Actor { }
    public static let shared = Actor()
}
