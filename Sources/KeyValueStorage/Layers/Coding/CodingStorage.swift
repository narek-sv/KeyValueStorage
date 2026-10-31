//
//  CodingStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - CodingStorageKey

public struct CodingStorageKey<Storage: AsyncDataStorage, Value: CodingValue>: Sendable {
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

// MARK: - CodingStorageKey + Hashable

extension CodingStorageKey: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key &&
        lhs.codingType == rhs.codingType
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(ObjectIdentifier(codingType))
    }
}

// MARK: - CodingStorageError

/// The errors a `CodingStorage` or an `AsyncCodingStorage` throws.
public enum CodingStorageError<Storage: AsyncDataStorage>: Swift.Error, Sendable {
    /// The underlying storage failed.
    case storage(Storage.Error)
    /// The coder couldn't encode or decode the value.
    case coding(any Swift.Error)
}

// MARK: - CodingStorage

/// Encodes values and passes them to a synchronous data storage, so code that uses it never needs `await`.
/// - Note: As thread-safe as its storage: `Sendable` when its storage is.
open class CodingStorage<Storage: DataStorage> {
    public typealias Error = CodingStorageError<Storage>

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
    
    public func fetch<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>) throws(Error) -> Value? {
        let data: Data?
        do throws(Storage.Error) {
            data = try storage.fetch(forKey: key.key)
        } catch {
            throw .storage(error)
        }

        guard let data else {
            return nil
        }

        return try coder.decoded(data, as: Value.self, for: Storage.self)
    }

    public func save<Value: CodingValue>(_ value: Value, forKey key: CodingStorageKey<Storage, Value>) throws(Error) {
        let encoded = try coder.encoded(value, for: Storage.self)
        do throws(Storage.Error) {
            try storage.save(encoded, forKey: key.key)
        } catch {
            throw .storage(error)
        }
    }

    public func set<Value: CodingValue>(_ value: Value?, forKey key: CodingStorageKey<Storage, Value>) throws(Error) {
        if let value {
            try save(value, forKey: key)
        } else {
            try delete(forKey: key)
        }
    }

    public func delete<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>) throws(Error) {
        do throws(Storage.Error) {
            try storage.delete(forKey: key.key)
        } catch {
            throw .storage(error)
        }
    }

    public func clear() throws(Error) {
        do throws(Storage.Error) {
            try storage.clear()
        } catch {
            throw .storage(error)
        }
    }
}

// MARK: - CodingStorage + Sendable

/// Unchecked only because the class is open: its state is immutable, and the coder and the storage are `Sendable`.
extension CodingStorage: @unchecked Sendable where Storage: Sendable { }
