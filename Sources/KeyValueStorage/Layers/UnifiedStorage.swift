//
//  UnifiedStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 11.12.23.
//

// MARK: - UnifiedStorageKey

public struct UnifiedStorageKey<Storage: KeyValueDataStorage, Value: CodingValue>: Sendable {
    public let key: Storage.Key
    public let scope: Storage.Scope
    public let codingType: Value.Type
    public let storageType: Storage.Type
    
    public init(key: Storage.Key, scope: Storage.Scope = .default) {
        self.key = key
        self.scope = scope
        self.codingType = Value.self
        self.storageType = Storage.self
    }
}

// MARK: - UnifiedStorageKey + Hashable

extension UnifiedStorageKey: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key &&
        lhs.scope == rhs.scope &&
        lhs.codingType == rhs.codingType &&
        lhs.storageType == rhs.storageType
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(scope)
        hasher.combine(ObjectIdentifier(codingType))
        hasher.combine(ObjectIdentifier(storageType))
    }
}

// MARK: - UnifiedStorageFactory

public protocol UnifiedStorageFactory: Sendable {
    func dataStorage<Storage: KeyValueDataStorage>(for scope: Storage.Scope) async throws(Storage.Error) -> Storage
    func codingStorage<Storage: KeyValueDataStorage>(for storage: Storage) async -> KeyValueCodingStorage<Storage>
}

// MARK: - DefaultUnifiedStorageFactory

open class DefaultUnifiedStorageFactory: UnifiedStorageFactory, @unchecked Sendable {
    let coder: DataCoder
    
    /// - Parameter coder: Encodes the values of every storage the factory creates.
    public init(coder: DataCoder = RawDataCoder()) {
        self.coder = coder
    }
    
    open func dataStorage<Storage: KeyValueDataStorage>(for scope: Storage.Scope) async throws(Storage.Error) -> Storage {
        try Storage(scope: scope)
    }
    
    open func codingStorage<Storage: KeyValueDataStorage>(for storage: Storage) async -> KeyValueCodingStorage<Storage> {
        KeyValueCodingStorage(storage: storage, coder: coder)
    }
}

// MARK: - ObservableUnifiedStorageFactory

/// Creates storages whose keys can be observed with `UnifiedStorage.publisher(forKey:)` and `stream(forKey:)`.
/// See `KeyValueObservableStorage` for when and where changes are delivered.
public final class ObservableUnifiedStorageFactory: DefaultUnifiedStorageFactory, @unchecked Sendable {
    public override func codingStorage<Storage: KeyValueDataStorage>(for storage: Storage) async -> KeyValueCodingStorage<Storage> {
        KeyValueObservableStorage(storage: storage, coder: coder)
    }
}

// MARK: - UnifiedStorage

public actor UnifiedStorage {
    
    // MARK: Type Aliases

    public typealias Key = UnifiedStorageKey
    
    // MARK: Properties
    
    private var storages = [AnyHashable: Any]()
    private let factory: UnifiedStorageFactory

    // MARK: Initializers

    public init(factory: UnifiedStorageFactory) {
        self.factory = factory
    }
    
    public init() {
        self.init(factory: DefaultUnifiedStorageFactory())
    }
    
    // MARK: Main Functionality
    
    public nonisolated func fetch<Storage: KeyValueDataStorage, Value: CodingValue>(forKey key: Key<Storage, Value>) async throws(KeyValueCodingStorage<Storage>.Error) -> Value? {
        let storage: KeyValueCodingStorage<Storage> = try await storage(for: key.scope)
        return try await storage.fetch(forKey: .init(key: key.key))
    }
    
    public nonisolated func save<Storage: KeyValueDataStorage, Value: CodingValue>(_ value: Value, forKey key: Key<Storage, Value>) async throws(KeyValueCodingStorage<Storage>.Error) {
        let storage: KeyValueCodingStorage<Storage> = try await storage(for: key.scope)
        try await storage.save(value, forKey: .init(key: key.key))
    }
    
    public nonisolated func set<Storage: KeyValueDataStorage, Value: CodingValue>(_ value: Value?, forKey key: Key<Storage, Value>) async throws(KeyValueCodingStorage<Storage>.Error) {
        let storage: KeyValueCodingStorage<Storage> = try await storage(for: key.scope)
        try await storage.set(value, forKey: .init(key: key.key))
    }
    
    public nonisolated func delete<Storage: KeyValueDataStorage, Value: CodingValue>(forKey key: Key<Storage, Value>) async throws(KeyValueCodingStorage<Storage>.Error) {
        let storage: KeyValueCodingStorage<Storage> = try await storage(for: key.scope)
        try await storage.delete(forKey: .init(key: key.key, codingType: key.codingType))
    }
    
    /// Removes everything stored in the given storage and scope.
    /// The storage is loaded on demand, so this also clears values saved in previous launches.
    public nonisolated func clear<Storage: KeyValueDataStorage>(storage: Storage.Type, forScope scope: Storage.Scope = .default) async throws(KeyValueCodingStorage<Storage>.Error) {
        let storage: KeyValueCodingStorage<Storage> = try await self.storage(for: scope)
        try await storage.clear()
    }
    
    // MARK: Observation
    
    /// Changes are delivered on a background executor; see `KeyValueObservableStorage`.
    /// - Parameter includingCurrentValue: Whether the publisher first emits the currently stored value, or `nil` if there's none.
    /// - Returns: `nil` if the storage isn't observable, i.e. it wasn't created by an `ObservableUnifiedStorageFactory`.
    public nonisolated func publisher<Storage: KeyValueDataStorage, Value: CodingValue>(forKey key: Key<Storage, Value>, includingCurrentValue: Bool = true)
    async throws(KeyValueCodingStorage<Storage>.Error) -> KeyValuePublisher<Value?>? {
        let storage: KeyValueCodingStorage<Storage> = try await storage(for: key.scope)
        let codingKey = KeyValueCodingStorageKey<Storage, Value>(key: key.key)
        return try await (storage as? KeyValueObservableStorage<Storage>)?.publisher(forKey: codingKey, includingCurrentValue: includingCurrentValue)
    }
    
    /// The stream resumes on the executor of the task that iterates it; see `KeyValueObservableStorage`.
    /// - Parameter includingCurrentValue: Whether the stream starts with the currently stored value, or `nil` if there's none.
    /// - Returns: `nil` if the storage isn't observable, i.e. it wasn't created by an `ObservableUnifiedStorageFactory`.
    public nonisolated func stream<Storage: KeyValueDataStorage, Value: CodingValue>(forKey key: Key<Storage, Value>, includingCurrentValue: Bool = true)
    async throws(KeyValueCodingStorage<Storage>.Error) -> AsyncStream<Value?>? {
        let storage: KeyValueCodingStorage<Storage> = try await storage(for: key.scope)
        let codingKey = KeyValueCodingStorageKey<Storage, Value>(key: key.key)
        return try await (storage as? KeyValueObservableStorage<Storage>)?.stream(forKey: codingKey, includingCurrentValue: includingCurrentValue)
    }
    
    // MARK: Helpers
    
    /// Caches the creation task before awaiting it, so concurrent first calls share one storage instead of
    /// each creating their own while the actor is suspended. Failures aren't cached, so a later call can retry.
    private func storage<Storage: KeyValueDataStorage>(for scope: Storage.Scope) async throws(KeyValueCodingStorage<Storage>.Error) -> KeyValueCodingStorage<Storage> {
        let underlyingKey = UnderlyingStorageKey<Storage>(scope: scope)
        let task: CreationTask<Storage>
        if let cached = storages[underlyingKey] as? CreationTask<Storage> {
            task = cached
        } else {
            let factory = factory
            task = Task {
                do throws(Storage.Error) {
                    let dataStorage: Storage = try await factory.dataStorage(for: scope)
                    return .success(await factory.codingStorage(for: dataStorage))
                } catch {
                    return .failure(error)
                }
            }
            storages[underlyingKey] = task
        }

        switch await task.value {
        case let .success(storage):
            return storage
        case let .failure(error):
            if let cached = storages[underlyingKey] as? CreationTask<Storage>, cached == task {
                storages[underlyingKey] = nil
            }

            throw .storage(error)
        }
    }

    /// Creation can't fail with a typed error inside a `Task`, so the task returns its outcome instead.
    private typealias CreationTask<Storage: KeyValueDataStorage> = Task<Result<KeyValueCodingStorage<Storage>, Storage.Error>, Never>
}

// MARK: - UnifiedStorage + UnderlyingStorageKey

extension UnifiedStorage {
    private struct UnderlyingStorageKey<Storage: KeyValueDataStorage>: Hashable, Sendable {
        let scope: Storage.Scope
        let storageType: Storage.Type
        
        init(scope: Storage.Scope) {
            self.scope = scope
            self.storageType = Storage.self
        }
        
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.scope == rhs.scope &&
            lhs.storageType == rhs.storageType
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(scope)
            hasher.combine(ObjectIdentifier(storageType))
        }
    }
}
