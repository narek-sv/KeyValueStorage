//
//  AsyncKeyValueCodingStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.10.26.
//

import Foundation

// MARK: - AsyncKeyValueCodingStorage

/// Encodes values and passes them to any data storage, synchronous or not.
/// It holds only immutable state, so it doesn't need an actor: encoding runs in parallel on the callers' tasks.
open class AsyncKeyValueCodingStorage<Storage: AsyncKeyValueDataStorage>: @unchecked Sendable {
    public typealias Error = KeyValueCodingError<Storage>

    // MARK: Properties

    private let coder: any DataCoder
    private let storage: Storage
    
    public var scope: Storage.Scope {
        storage.scope
    }
    
    // MARK: Initializers
    
    public init(storage: Storage, coder: any DataCoder = RawDataCoder()) {
        self.coder = coder
        self.storage = storage
    }
    
    // MARK: Main Functionality
    
    public func fetch<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws(Error) -> Value? {
        let data: Data?
        do throws(Storage.Error) {
            data = try await storage.fetch(forKey: key.key)
        } catch {
            throw .storage(error)
        }

        guard let data else {
            return nil
        }

        return try coder.decoded(data, as: Value.self, for: Storage.self)
    }

    public func save<Value: CodingValue>(_ value: Value, forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws(Error) {
        let encoded = try coder.encoded(value, for: Storage.self)
        do throws(Storage.Error) {
            try await storage.save(encoded, forKey: key.key)
        } catch {
            throw .storage(error)
        }
    }

    public func set<Value: CodingValue>(_ value: Value?, forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws(Error) {
        if let value {
            try await save(value, forKey: key)
        } else {
            try await delete(forKey: key)
        }
    }

    public func delete<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws(Error) {
        do throws(Storage.Error) {
            try await storage.delete(forKey: key.key)
        } catch {
            throw .storage(error)
        }
    }

    public func clear() async throws(Error) {
        do throws(Storage.Error) {
            try await storage.clear()
        } catch {
            throw .storage(error)
        }
    }
}
