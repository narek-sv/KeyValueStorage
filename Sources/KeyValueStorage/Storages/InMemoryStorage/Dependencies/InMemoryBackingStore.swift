//
//  InMemoryBackingStore.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import Foundation

// MARK: - InMemoryBackingStore

/// - Note: Buckets and keys are their exact bytes, as in the other storages: `"é"` and `"e\u{301}"` are two keys.
public protocol InMemoryBackingStore {
    func read(forKey key: String, in bucket: String) -> Data?
    func write(_ data: Data, forKey key: String, in bucket: String)
    func remove(forKey key: String, in bucket: String)
    func removeAll(in bucket: String)
}

// MARK: - DefaultInMemoryBackingStoreWrapper

/// The process-wide memory.
/// - Warning: Subclasses inherit `Sendable`: their own state must be thread-safe too.
open class DefaultInMemoryBackingStoreWrapper: InMemoryBackingStore, @unchecked Sendable {
    private static let lock = Lock()
    // Bytes, not `String`: Swift's `==` takes `"é"` and `"e\u{301}"` for one key
    nonisolated(unsafe) private static var buckets = [Data: [Data: Data]]()
    
    public init() { }
    
    open func read(forKey key: String, in bucket: String) -> Data? {
        Self.lock.withLock {
            Self.buckets[Self.bytes(bucket)]?[Self.bytes(key)]
        }
    }
    
    open func write(_ data: Data, forKey key: String, in bucket: String) {
        _ = Self.lock.withLock {
            Self.buckets[Self.bytes(bucket), default: [:]].updateValue(data, forKey: Self.bytes(key))
        } // old value freed after unlock
    }

    open func remove(forKey key: String, in bucket: String) {
        _ = Self.lock.withLock {
            Self.buckets[Self.bytes(bucket)]?.removeValue(forKey: Self.bytes(key))
        } // old value freed after unlock
    }

    open func removeAll(in bucket: String) {
        _ = Self.lock.withLock {
            Self.buckets.removeValue(forKey: Self.bytes(bucket))
        } // old value freed after unlock
    }

    private static func bytes(_ name: String) -> Data {
        Data(name.utf8)
    }
}
