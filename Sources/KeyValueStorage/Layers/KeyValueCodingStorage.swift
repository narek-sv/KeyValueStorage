//
//  KeyValueCodingStorage.swift
//  
//
//  Created by Narek Sahakyan on 11.12.23.
//

// MARK: - KeyValueCodingStorageKey

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

// MARK: - KeyValueCodingStorageKey + Hashable

extension KeyValueCodingStorageKey: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key &&
        lhs.codingType == rhs.codingType
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(ObjectIdentifier(codingType))
    }
}

// MARK: - KeyValueCodingStorage

/// Encodes values and passes them to the underlying data storage.
/// It holds only immutable state, so it doesn't need an actor: encoding runs in parallel on the callers' tasks.
open class KeyValueCodingStorage<Storage: KeyValueDataStorage>: @unchecked Sendable {
    
    // MARK: Properties

    private let coder: DataCoder
    private let storage: Storage
    
    public var domain: Storage.Domain {
        storage.domain
    }
    
    // MARK: Initializers
    
    public init(storage: Storage, coder: DataCoder = RawDataCoder()) {
        self.coder = coder
        self.storage = storage
    }
    
    // MARK: Main Functionality
    
    public func fetch<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws -> Value? {
        if let data = try storage.fetch(forKey: key.key) {
            // Explicit, because the return type would otherwise make the coder decode `Value?`
            return try await coder.decode(data) as Value
        }
        
        return nil
    }
    
    public func save<Value: CodingValue>(_ value: Value, forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws {
        let encoded = try await coder.encode(value)
        try storage.save(encoded, forKey: key.key)
    }
    
    public func set<Value: CodingValue>(_ value: Value?, forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws {
        if let value {
            try await save(value, forKey: key)
        } else {
            try await delete(forKey: key)
        }
    }
    
    public func delete<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws {
        try storage.delete(forKey: key.key)
    }
    
    public func clear() async throws {
        try storage.clear()
    }
}

// MARK: - CodingStorageActor

/// Serializes the observation registry and the delivery of changes to `KeyValueObservableStorage` subscribers.
@globalActor
public final class CodingStorageActor {
    public actor Actor { }
    public static let shared = Actor()
}
