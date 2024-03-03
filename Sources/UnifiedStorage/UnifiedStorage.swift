//
//  UnifiedStorage.swift
//  
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Combine

// MARK: - Unified Storage Key

public struct UnifiedStorageKey<Storage: KeyValueDataStorage, Value: CodingValue>: Sendable {
    public let key: Storage.Key
    public let domain: Storage.Domain?
    public let codingType: Value.Type
    public let storageType: Storage.Type
    
    public init(key: Storage.Key, domain: Storage.Domain? = nil) {
        self.key = key
        self.domain = domain
        self.codingType = Value.self
        self.storageType = Storage.self
    }
}

extension UnifiedStorageKey: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key &&
        lhs.domain == rhs.domain &&
        lhs.codingType == rhs.codingType &&
        lhs.storageType == rhs.storageType
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(domain)
        hasher.combine(String(describing: codingType))
        hasher.combine(String(describing: storageType))
    }
}

// MARK: - Unified Storage Factory

public protocol UnifiedStorageFactory {
    func dataStorage<Storage: KeyValueDataStorage>(for domain: Storage.Domain?) async throws -> Storage
    func codingStorage<Storage: KeyValueDataStorage>(for storage: Storage) throws -> KeyValueCodingStorage<Storage>
}

open class DefaultUnifiedStorageFactory: UnifiedStorageFactory {
    public func dataStorage<Storage: KeyValueDataStorage>(for domain: Storage.Domain?) async throws -> Storage {
        if let domain {
            return try await Storage(domain: domain)
        }
        
        return try await Storage()
    }
    
    public func codingStorage<Storage: KeyValueDataStorage>(for storage: Storage) throws -> KeyValueCodingStorage<Storage> {
        KeyValueCodingStorage(storage: storage)
    }
}

public final class ObservableUnifiedStorageFactory: DefaultUnifiedStorageFactory {
    public override func codingStorage<Storage: KeyValueDataStorage>(for storage: Storage) throws -> KeyValueCodingStorage<Storage> {
        KeyValueObservableStorage(storage: storage)
    }
}

// MARK: - Unified Storage

public actor UnifiedStorage {
    
    // MARK: Type Aliases

    public typealias Key = UnifiedStorageKey
    
    // MARK: Properties
    
    private var storages = [AnyHashable?: Any]()
    private let factory: UnifiedStorageFactory

    // MARK: Initializers

    public init(factory: UnifiedStorageFactory) {
        self.factory = factory
    }
    
    public init() {
        self.init(factory: DefaultUnifiedStorageFactory())
    }
    
    // MARK: Main Functionality
    
    public func fetch<Storage: KeyValueDataStorage, Value: CodingValue>(forKey key: Key<Storage, Value>) async throws -> Value? {
        let storage: KeyValueCodingStorage<Storage> = try await storage(for: key.domain)
        return try await storage.fetch(forKey: .init(key: key.key))
    }
    
    public func save<Storage: KeyValueDataStorage, Value: CodingValue>(_ value: Value, forKey key: Key<Storage, Value>) async throws {
        let storage: KeyValueCodingStorage<Storage> = try await storage(for: key.domain)
        try await storage.save(value, forKey: .init(key: key.key))
    }
    
    public func set<Storage: KeyValueDataStorage, Value: CodingValue>(_ value: Value?, forKey key: Key<Storage, Value>) async throws {
        let storage: KeyValueCodingStorage<Storage> = try await storage(for: key.domain)
        try await storage.set(value, forKey: .init(key: key.key))
    }
    
    public func delete<Storage: KeyValueDataStorage, Value: CodingValue>(forKey key: Key<Storage, Value>) async throws {
        let storage: KeyValueCodingStorage<Storage> = try await storage(for: key.domain)
        try await storage.delete(forKey: .init(key: key.key, codingType: key.codingType))
    }
    
    public func clear<Storage: KeyValueDataStorage>(storage: Storage.Type, forDomain domain: Storage.Domain?) async throws {
        let storage: KeyValueCodingStorage<Storage> = try await self.storage(for: domain)
        try await storage.clear()
    }
    
    public func clear<Storage: KeyValueDataStorage>(storage: Storage.Type) async throws {
        for storage in storages.values {
            if let casted = storage as? KeyValueCodingStorage<Storage> {
                try await casted.clear()
            }
        }
    }
    
    public func clear() async throws {
        for storage in storages.values {
            if let casted = storage as? Clearing {
                try await casted.clear()
            }
        }
    }
    
    // MARK: - Observation
    
    public func publisher<Storage: KeyValueDataStorage, Value: CodingValue>(forKey key: Key<Storage, Value>)
    async throws -> AnyPublisher<Value?, Never>? {
        let storage: KeyValueCodingStorage<Storage> = try await storage(for: key.domain)
        let codingKey = KeyValueCodingStorageKey<Storage, Value>(key: key.key)
        return await (storage as? KeyValueObservableStorage<Storage>)?.publisher(forKey: codingKey)
    }
    
    public func stream<Storage: KeyValueDataStorage, Value: CodingValue>(forKey key: Key<Storage, Value>)
    async throws -> AsyncStream<Value?>? {
        let storage: KeyValueCodingStorage<Storage> = try await storage(for: key.domain)
        let codingKey = KeyValueCodingStorageKey<Storage, Value>(key: key.key)
        return await (storage as? KeyValueObservableStorage<Storage>)?.stream(forKey: codingKey)
    }
    
    // MARK: Helpers
    
    private func storage<Storage: KeyValueDataStorage>(for domain: Storage.Domain?) async throws -> KeyValueCodingStorage<Storage> {
        let underlyingKey = UnderlyingStorageKey<Storage>(domain: domain)
        if let storage = storages[underlyingKey], let casted = storage as? KeyValueCodingStorage<Storage> {
            return casted
        }
        
        let dataStorage: Storage = try await factory.dataStorage(for: domain)
        let codingStorage = try factory.codingStorage(for: dataStorage)
        storages[underlyingKey] = codingStorage
      
        
        return codingStorage
    }
}

extension UnifiedStorage {
    private struct UnderlyingStorageKey<Storage: KeyValueDataStorage>: Hashable, Sendable {
        let domain: Storage.Domain?
        let storageType: Storage.Type
        
        init(domain: Storage.Domain?) {
            self.domain = domain
            self.storageType = Storage.self
        }
        
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.domain == rhs.domain &&
            lhs.storageType == rhs.storageType
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(domain)
            hasher.combine(String(describing: storageType))
        }
    }
}
