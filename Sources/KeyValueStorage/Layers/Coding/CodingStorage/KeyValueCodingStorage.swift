//
//  KeyValueCodingStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - KeyValueCodingStorageKey

public struct KeyValueCodingStorageKey<Storage: AsyncKeyValueDataStorage, Value: CodingValue>: Sendable {
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

// MARK: - KeyValueCodingError

/// The errors a `KeyValueCodingStorage` or an `AsyncKeyValueCodingStorage` throws.
public enum KeyValueCodingError<Storage: AsyncKeyValueDataStorage>: Swift.Error, Sendable {
    /// The underlying storage failed.
    case storage(Storage.Error)
    /// The coder couldn't encode or decode the value.
    case coding(any Swift.Error)
}

// MARK: - KeyValueCodingStorage

/// Encodes values and passes them to a synchronous data storage, so code that uses it never needs `await`.
/// - Note: As thread-safe as its storage: `Sendable` when its storage is.
open class KeyValueCodingStorage<Storage: KeyValueDataStorage> {
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
    
    public func fetch<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) throws(Error) -> Value? {
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

    public func save<Value: CodingValue>(_ value: Value, forKey key: KeyValueCodingStorageKey<Storage, Value>) throws(Error) {
        let encoded = try coder.encoded(value, for: Storage.self)
        do throws(Storage.Error) {
            try storage.save(encoded, forKey: key.key)
        } catch {
            throw .storage(error)
        }
    }

    public func set<Value: CodingValue>(_ value: Value?, forKey key: KeyValueCodingStorageKey<Storage, Value>) throws(Error) {
        if let value {
            try save(value, forKey: key)
        } else {
            try delete(forKey: key)
        }
    }

    public func delete<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) throws(Error) {
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

// MARK: - KeyValueCodingStorage + Sendable

/// Unchecked only because the class is open: its state is immutable, and the coder and the storage are `Sendable`.
extension KeyValueCodingStorage: @unchecked Sendable where Storage: Sendable { }

// MARK: - CodingStorageActor

/// Serializes the observation registry and the delivery of changes to `KeyValueObservableStorage` subscribers.
@globalActor
public final class CodingStorageActor {
    public actor Actor { }
    public static let shared = Actor()
}
