//
//  InMemoryBackingStore.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import Foundation

// MARK: - InMemoryBackingStore

public protocol InMemoryBackingStore {
    func read(forKey key: String, in bucket: String?) -> Data?
    func write(_ data: Data, forKey key: String, in bucket: String?)
    func remove(forKey key: String, in bucket: String?)
    func removeAll(in bucket: String?)
}

// MARK: - DefaultInMemoryBackingStoreWrapper

/// The process-wide memory.
/// - Warning: Subclasses inherit `Sendable`: their own state must be thread-safe too.
open class DefaultInMemoryBackingStoreWrapper: InMemoryBackingStore, @unchecked Sendable {
    private static let lock = Lock()
    nonisolated(unsafe) private static var buckets = [String?: [String: Data]]()
    
    public init() { }
    
    open func read(forKey key: String, in bucket: String?) -> Data? {
        Self.lock.withLock {
            Self.buckets[bucket]?[key]
        }
    }
    
    open func write(_ data: Data, forKey key: String, in bucket: String?) {
        _ = Self.lock.withLock {
            Self.buckets[bucket, default: [:]].updateValue(data, forKey: key)
        } // old value freed after unlock
    }

    open func remove(forKey key: String, in bucket: String?) {
        _ = Self.lock.withLock {
            Self.buckets[bucket]?.removeValue(forKey: key)
        } // old value freed after unlock
    }

    open func removeAll(in bucket: String?) {
        _ = Self.lock.withLock {
            Self.buckets.removeValue(forKey: bucket)
        } // old value freed after unlock
    }
}
