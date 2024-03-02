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
    
    public init(key: Storage.Key, domain: Storage.Domain? = nil) {
        self.key = key
        self.domain = domain
        self.codingType = Value.self
    }
}

extension UnifiedStorageKey: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key &&
        lhs.domain == rhs.domain &&
        lhs.codingType == rhs.codingType
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(domain)
        hasher.combine(String(describing: codingType))
    }
}

public extension UnifiedStorageKey {
    static func userDefaults(key: Storage.Key, domain: Storage.Domain? = nil) -> UnifiedStorageKey<Storage, Value>
    where Storage == UserDefaultsStorage {
        .init(key: key, domain: domain)
    }
    
    static func keychain(key: Storage.Key, domain: Storage.Domain? = nil) -> UnifiedStorageKey<Storage, Value>
    where Storage == KeychainStorage {
        .init(key: key, domain: domain)
    }
    
    static func inMemory(key: Storage.Key, domain: Storage.Domain? = nil) -> UnifiedStorageKey<Storage, Value>
    where Storage == InMemoryStorage {
        .init(key: key, domain: domain)
    }
    
    static func file(key: Storage.Key, domain: Storage.Domain? = nil) -> UnifiedStorageKey<Storage, Value>
    where Storage == FileStorage {
        .init(key: key, domain: domain)
    }
}

// MARK: - Unified Storage Domain

public struct UnifiedStorageDomain<Storage: KeyValueDataStorage>: Sendable {
    public let domain: Storage.Domain?
    
    public init(domain: Storage.Domain? = nil) {
        self.domain = domain
    }
    
    public init<Value: CodingValue>(key: UnifiedStorageKey<Storage, Value>) {
        self.domain = key.domain
    }
}

// MARK: - Unified Storage Factory

public protocol UnifiedStorageFactory {
    func dataStorage<Storage: KeyValueDataStorage>(for domain: UnifiedStorageDomain<Storage>) async throws -> Storage
    func codingStorage<Storage: KeyValueDataStorage>(for storage: Storage) throws -> KeyValueCodingStorage<Storage>
}

open class DefaultUnifiedStorageFactory: UnifiedStorageFactory {
    public func dataStorage<Storage: KeyValueDataStorage>(for domain: UnifiedStorageDomain<Storage>) async throws -> Storage {
        if let domain = domain.domain {
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
        let storage = try await storage(for: .init(key: key))
        return try await storage.fetch(forKey: .init(key: key.key))
    }
    
    public func save<Storage: KeyValueDataStorage, Value: CodingValue>(_ value: Value, forKey key: Key<Storage, Value>) async throws {
        let storage = try await storage(for: .init(key: key))
        try await storage.save(value, forKey: .init(key: key.key))
    }
    
    public func set<Storage: KeyValueDataStorage, Value: CodingValue>(_ value: Value?, forKey key: Key<Storage, Value>) async throws {
        let storage = try await storage(for: .init(key: key))
        try await storage.set(value, forKey: .init(key: key.key))
    }
    
    public func delete<Storage: KeyValueDataStorage, Value: CodingValue>(forKey key: Key<Storage, Value>) async throws {
        let storage = try await storage(for: .init(key: key))
        try await storage.delete(forKey: .init(key: key.key, codingType: key.codingType))
    }
    
    public func clear<Storage: KeyValueDataStorage>(storage: Storage.Type, forDomain domain: Storage.Domain) async throws {
        let storage = try? await self.storage(for: UnifiedStorageDomain<Storage>(domain: domain))
        try await storage?.clear()
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
            if let casted = storage as? (any KeyValueDataStorage) {
                try await casted.clear()
            }
        }
    }
    
    // MARK: Helpers
    
    private func storage<Storage: KeyValueDataStorage>(for domain: UnifiedStorageDomain<Storage>) async throws -> KeyValueCodingStorage<Storage> {
        if let storage = storages[domain.domain], let casted = storage as? KeyValueCodingStorage<Storage> {
            return casted
        }
        
        let dataStorage = try await factory.dataStorage(for: domain)
        let codingStorage = try factory.codingStorage(for: dataStorage)
        storages[domain.domain] = codingStorage
        return codingStorage
    }
    
//    private func storage<Storage: KeyValueDataStorage>(for domain: UnifiedStorageDomain<Storage>) async throws -> KeyValueCodingStorage<Storage> {
//        if let storage = storages[domain.domain], let casted = storage as? KeyValueCodingStorage<Storage> {
//            return casted
//        }
//        
//        let dataStorage = try await factory.dataStorage(for: domain)
//        let codingStorage = try factory.codingStorage(for: dataStorage)
//        storages[domain.domain] = codingStorage
//        return codingStorage
//    }
}
