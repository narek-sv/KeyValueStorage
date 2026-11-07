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

    public var codingType: Value.Type {
        Value.self
    }
    
    public init(key: Storage.Key) {
        self.key = key
    }
}

// MARK: - CodingStorageKey + String

public extension CodingStorageKey where Storage.Key == ExactString {
    /// Any string as the key, such as one made at runtime, compared by its exact bytes.
    init(key: String) {
        self.init(key: ExactString(key))
    }
}

// MARK: - CodingStorageKey + Hashable

/// Keys of other value types are other types, so `==` compares only the key; the hash also mixes in the value type, for
/// dictionaries of `AnyHashable` keys.
extension CodingStorageKey: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key
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
/// - Warning: Subclasses inherit `Sendable`: their own state must be thread-safe too.
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
    
    open func fetch<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>) throws(Error) -> Value? {
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

    open func save<Value: CodingValue>(_ value: Value, forKey key: CodingStorageKey<Storage, Value>) throws(Error) {
        let encoded = try coder.encoded(value, for: Storage.self)
        do throws(Storage.Error) {
            try storage.save(encoded, forKey: key.key)
        } catch {
            throw .storage(error)
        }
    }

    /// Saves `value`, or deletes the stored one if `nil`, through the storage's `set`.
    /// - Note: It doesn't call `save` or `delete`: a subclass that changes them changes this too.
    open func set<Value: CodingValue>(_ value: Value?, forKey key: CodingStorageKey<Storage, Value>) throws(Error) {
        var encoded: Data?
        if let value {
            encoded = try coder.encoded(value, for: Storage.self)
        }

        do throws(Storage.Error) {
            try storage.set(encoded, forKey: key.key)
        } catch {
            throw .storage(error)
        }
    }

    open func delete<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>) throws(Error) {
        do throws(Storage.Error) {
            try storage.delete(forKey: key.key)
        } catch {
            throw .storage(error)
        }
    }

    open func clear() throws(Error) {
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
