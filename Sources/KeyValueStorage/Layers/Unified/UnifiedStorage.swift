//
//  UnifiedStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 11.12.23.
//

// MARK: - UnifiedStorage

/// One entry point for every storage, keyed by typed keys.
///
/// - It adds no isolation of its own, so it's safe to call from any thread, task or actor, and calls on storages of
///   different types or scopes never wait for each other. Only `Sendable` storages compile as keys (`UnifiedStorable`):
///   the built-in storages are thread-safe, and `IsolatedDataStorage` makes any other one shareable.
/// - It creates one storage per storage type and scope, on first use, through its factory.
/// - When its factory makes a storage observable, the changes made through it are published; see `ObservableStorage`.
public final class UnifiedStorage: @unchecked Sendable {
    
    // MARK: Type Aliases

    public typealias Key = UnifiedStorageKey
    
    // MARK: Properties
    
    private let factory: any UnifiedStorageFactory
    /// The creation task of each storage type and scope; held only to look up or insert, never across an `await`.
    private let lock = Lock()
    private var storages = [AnyHashable: any Sendable]()

    // MARK: Initializers

    public init(factory: any UnifiedStorageFactory) {
        self.factory = factory
    }
    
    public init(observable: Bool = false) {
        self.factory = observable ? ObservableUnifiedStorageFactory() : DefaultUnifiedStorageFactory()
    }
    
    // MARK: Main Functionality
    
    public func fetch<Storage: UnifiedStorable, Value: CodingValue>(forKey key: Key<Storage, Value>) async throws(CodingStorageError<Storage>) -> Value? {
        let entry: Entry<Storage> = try await storage(for: key.scope)
        if let observable = entry.observable {
            return try await observable.fetch(forKey: .init(key: key.key))
        }

        return try await entry.coding.fetch(forKey: .init(key: key.key))
    }
    
    public func save<Storage: UnifiedStorable, Value: CodingValue>(_ value: Value, forKey key: Key<Storage, Value>) async throws(CodingStorageError<Storage>) {
        let entry: Entry<Storage> = try await storage(for: key.scope)
        if let observable = entry.observable {
            try await observable.save(value, forKey: .init(key: key.key))
        } else {
            try await entry.coding.save(value, forKey: .init(key: key.key))
        }
    }
    
    public func set<Storage: UnifiedStorable, Value: CodingValue>(_ value: Value?, forKey key: Key<Storage, Value>) async throws(CodingStorageError<Storage>) {
        if let value {
            try await save(value, forKey: key)
        } else {
            try await delete(forKey: key)
        }
    }
    
    public func delete<Storage: UnifiedStorable, Value: CodingValue>(forKey key: Key<Storage, Value>) async throws(CodingStorageError<Storage>) {
        let entry: Entry<Storage> = try await storage(for: key.scope)
        if let observable = entry.observable {
            try await observable.delete(forKey: .init(key: key.key, codingType: key.codingType))
        } else {
            try await entry.coding.delete(forKey: .init(key: key.key, codingType: key.codingType))
        }
    }
    
    /// Removes everything stored in the given storage and scope.
    /// The storage is loaded on demand, so this also clears values saved in previous launches.
    public func clear<Storage: UnifiedStorable>(storage: Storage.Type, forScope scope: Storage.Scope = .default) async throws(CodingStorageError<Storage>) {
        let entry: Entry<Storage> = try await self.storage(for: scope)
        if let observable = entry.observable {
            try await observable.clear()
        } else {
            try await entry.coding.clear()
        }
    }
    
    // MARK: Observation
    
    /// Changes are delivered on the thread that makes them; see `ObservableStorage`.
    /// - Parameter includingCurrentValue: Whether the publisher first emits the currently stored value, or `nil` if there's none.
    /// - Returns: `nil` if the factory doesn't make the key's storage observable.
    public func publisher<Storage: UnifiedStorable, Value: CodingValue>(forKey key: Key<Storage, Value>, includingCurrentValue: Bool = true)
    async throws(CodingStorageError<Storage>) -> ValuePublisher<Value?>? {
        let entry: Entry<Storage> = try await storage(for: key.scope)
        return try await entry.observable?.publisher(forKey: .init(key: key.key), includingCurrentValue: includingCurrentValue)
    }
    
    /// The stream resumes on the executor of the task that iterates it; see `ObservableStorage`.
    /// - Parameter includingCurrentValue: Whether the stream starts with the currently stored value, or `nil` if there's none.
    /// - Returns: `nil` if the factory doesn't make the key's storage observable.
    public func stream<Storage: UnifiedStorable, Value: CodingValue>(forKey key: Key<Storage, Value>, includingCurrentValue: Bool = true)
    async throws(CodingStorageError<Storage>) -> AsyncStream<Value?>? {
        let entry: Entry<Storage> = try await storage(for: key.scope)
        return try await entry.observable?.stream(forKey: .init(key: key.key), includingCurrentValue: includingCurrentValue)
    }
    
    // MARK: Helpers
    
    /// Caches the creation task before awaiting it, so concurrent first calls share one storage instead of
    /// each creating their own. Failures aren't cached, so a later call can retry.
    private func storage<Storage: UnifiedStorable>(for scope: Storage.Scope) async throws(CodingStorageError<Storage>) -> Entry<Storage> {
        let underlyingKey = UnderlyingStorageKey<Storage>(scope: scope)
        let factory = factory
        let task = lock.withLock { () -> CreationTask<Storage> in
            if let cached = storages[underlyingKey] as? CreationTask<Storage> {
                return cached
            }

            let task = CreationTask<Storage> {
                do throws(Storage.Error) {
                    let dataStorage: Storage = try await factory.dataStorage(for: scope)
                    let coding = await factory.codingStorage(for: dataStorage)
                    return .success(Entry(coding: coding, observable: await factory.observableStorage(for: coding)))
                } catch {
                    return .failure(error)
                }
            }

            storages[underlyingKey] = task
            return task
        }

        switch await task.value {
        case let .success(storage):
            return storage
        case let .failure(error):
            lock.withLock {
                if storages[underlyingKey] as? CreationTask<Storage> == task {
                    storages[underlyingKey] = nil
                }
            }

            throw .storage(error)
        }
    }

    /// Creation can't fail with a typed error inside a `Task`, so the task returns its outcome instead.
    private typealias CreationTask<Storage: UnifiedStorable> = Task<Result<Entry<Storage>, Storage.Error>, Never>

    /// A storage type and scope's coding storage, and the factory's observable one; every call goes through the observable one when there is one.
    private struct Entry<Storage: UnifiedStorable>: Sendable {
        let coding: AsyncCodingStorage<Storage>
        let observable: ObservableStorage<Storage>?
    }
}

// MARK: - UnifiedStorage + UnderlyingStorageKey

extension UnifiedStorage {
    private struct UnderlyingStorageKey<Storage: UnifiedStorable>: Hashable, Sendable {
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
