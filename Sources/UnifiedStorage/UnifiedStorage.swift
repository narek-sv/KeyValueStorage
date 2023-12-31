//
//  UnifiedStorage.swift
//  
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Combine

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

public struct UnifiedStorageDomain<Storage: KeyValueDataStorage>: Sendable {
    public let domain: Storage.Domain?
    
    public init(domain: Storage.Domain? = nil) {
        self.domain = domain
    }
    
    public init<Value: CodingValue>(key: UnifiedStorageKey<Storage, Value>) {
        self.domain = key.domain
    }
}

public protocol UnifiedStorageFactory {
    func dataStorage<Storage: KeyValueDataStorage>(for domain: UnifiedStorageDomain<Storage>) throws -> Storage
    func codingStorage<Storage: KeyValueDataStorage>(for storage: Storage) throws -> KeyValueCodingStorage<Storage>
}

open class DefaultUnifiedStorageFactory: UnifiedStorageFactory {
    public func dataStorage<Storage: KeyValueDataStorage>(for domain: UnifiedStorageDomain<Storage>) throws -> Storage {
        try Storage(domain: domain.domain)
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

public actor UnifiedStorage {
    public typealias Key = UnifiedStorageKey
    
    private var storages = [AnyHashable?: Any]()
    private let factory: UnifiedStorageFactory

    public init(factory: UnifiedStorageFactory) {
        self.factory = factory
    }
    
    public init() {
        self.init(factory: DefaultUnifiedStorageFactory())
    }
    
    public func fetch<Storage: KeyValueDataStorage, Value: CodingValue>(forKey key: Key<Storage, Value>) async throws -> Value? {
        let storage = try storage(for: .init(key: key))
        return try await storage.fetch(forKey: key)
    }
    
    public func save<Storage: KeyValueDataStorage, Value: CodingValue>(_ value: Value, forKey key: Key<Storage, Value>) async throws {
        let storage = try storage(for: .init(key: key))
        try await storage.save(value, forKey: key)
    }
    
    public func set<Storage: KeyValueDataStorage, Value: CodingValue>(_ value: Value?, forKey key: Key<Storage, Value>) async throws {
        let storage = try storage(for: .init(key: key))
        try await storage.set(value, forKey: key)
    }
    
    public func delete<Storage: KeyValueDataStorage, Value: CodingValue>(forKey key: Key<Storage, Value>) async throws {
        let storage = try storage(for: .init(key: key))
        try await storage.delete(forKey: key)
    }
    
    public func clear<Storage: KeyValueDataStorage>(storage: Storage.Type, forDomain domain: Storage.Domain) async throws {
        let storage = try? self.storage(for: UnifiedStorageDomain<Storage>(domain: domain))
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
    
    private func storage<Storage: KeyValueDataStorage>(for domain: UnifiedStorageDomain<Storage>) throws -> KeyValueCodingStorage<Storage> {
        if let storage = storages[domain.domain], let casted = storage as? KeyValueCodingStorage<Storage> {
            return casted
        }
        
        let dataStorage = try factory.dataStorage(for: domain)
        let codingStorage = try factory.codingStorage(for: dataStorage)
        storages[domain.domain] = codingStorage
        return codingStorage
    }
}
