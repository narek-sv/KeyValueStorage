//
//  KeyValueCodingStorage.swift
//  
//
//  Created by Narek Sahakyan on 11.12.23.
//

public struct CodingKey<Storage: KeyValueDataStorage, Value: CodingValue>: Sendable {
    public let key: Storage.Key
    public let codingType: Value.Type
    
    public init(key: Storage.Key) {
        self.key = key
        self.codingType = Value.self
    }
    
    public init(key: Storage.Key, codingType: Value.Type) {
        self.key = key
        self.codingType = codingType
    }
}

open class KeyValueCodingStorage<Storage: KeyValueDataStorage>: @unchecked Sendable {
    private let coder: DataCoder
    private let storage: Storage
    
    public init(storage: Storage, coder: DataCoder = JSONDataCoder()) {
        self.coder = coder
        self.storage = storage
    }
    
    public func fetch<Value: CodingValue>(forKey key: Storage.Key) async throws -> Value? {
        if let data = try await storage.fetch(forKey: key) {
            return try await coder.decode(data)
        }
        
        return nil
    }
    
    public func save<Value: CodingValue>(_ value: Value, forKey key: Storage.Key) async throws {
        let encoded = try await coder.encode(value)
        try await storage.save(encoded, forKey: key)
    }
    
    public func set<Value: CodingValue>(_ value: Value?, forKey key: Storage.Key) async throws {
        if let value = value {
            try await save(value, forKey: key)
        } else {
            try await delete(forKey: key)
        }
    }
    
    public func delete(forKey key: Storage.Key) async throws {
        try await storage.delete(forKey: key)
    }
    
    public func clear() async throws {
        try await storage.clear()
    }
}
