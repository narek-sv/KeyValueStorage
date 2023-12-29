//
//  UnifiedStorage.swift
//  
//
//  Created by Narek Sahakyan on 11.12.23.
//

typealias UserDefaultsKey<Value: CodingValue> = UnifiedStorageKey<UserDefaultsStorage, Value>
typealias KeychainKey<Value: CodingValue> = UnifiedStorageKey<KeychainStorage, Value>

public struct UnifiedStorageKey<Storage: KeyValueDataStorage, Value: CodingValue>: Sendable {
    public let key: Storage.Key
    public let domain: Storage.Domain?
    public let codingType: Value.Type
    
    public init(key: Storage.Key, domain: Storage.Domain? = nil) {
        self.key = key
        self.domain = domain
        self.codingType = Value.self
    }
    
    public static func userDefaults(key: Storage.Key, domain: Storage.Domain? = nil) -> UnifiedStorageKey<Storage, Value>
    where Storage == UserDefaultsStorage {
        .init(key: key, domain: domain)
    }
    
    public static func keychain(key: Storage.Key, domain: Storage.Domain? = nil) -> UnifiedStorageKey<Storage, Value>
    where Storage == KeychainStorage {
        .init(key: key, domain: domain)
    }
    
    public static func inMemory(key: Storage.Key, domain: Storage.Domain? = nil) -> UnifiedStorageKey<Storage, Value>
    where Storage == InMemoryStorage {
        .init(key: key, domain: domain)
    }
    
    public static func file(key: Storage.Key, domain: Storage.Domain? = nil) -> UnifiedStorageKey<Storage, Value>
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

public final class DefaultUnifiedStorageFactory: UnifiedStorageFactory {
    public func dataStorage<Storage: KeyValueDataStorage>(for domain: UnifiedStorageDomain<Storage>) throws -> Storage {
        try Storage(domain: domain.domain)
    }
    
    public func codingStorage<Storage: KeyValueDataStorage>(for storage: Storage) throws -> KeyValueCodingStorage<Storage> {
        KeyValueCodingStorage(storage: storage)
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
        return try await storage.fetch(forKey: key.key)
    }
    
    public func save<Storage: KeyValueDataStorage, Value: CodingValue>(_ value: Value, forKey key: Key<Storage, Value>) async throws {
        let storage = try storage(for: .init(key: key))
        try await storage.save(value, forKey: key.key)
    }
    
    public func set<Storage: KeyValueDataStorage, Value: CodingValue>(_ value: Value?, forKey key: Key<Storage, Value>) async throws {
        if let value = value {
            try await save(value, forKey: key)
        } else {
            try await delete(forKey: key)
        }
    }
    
    public func delete<Storage: KeyValueDataStorage, Value: CodingValue>(forKey key: Key<Storage, Value>) async throws {
        let storage = try storage(for: .init(key: key))
        try await storage.delete(forKey: key.key)
    }
    
    public func clear<Storage: KeyValueDataStorage>(storage: Storage.Type, forDomain domain: Storage.Domain) async throws {
        let storage = try? self.storage(for: UnifiedStorageDomain<Storage>(domain: domain))
        try await storage?.clear()
        self.storages[domain] = nil
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
