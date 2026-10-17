//
//  InMemoryBackingStore.swift
//  KeyValueStorage
//
//  Created by nsahakyan@servicetitan.com on 17.10.26.
//

import Foundation

// MARK: - InMemoryBackingStore

public protocol InMemoryBackingStore {
    func read(forKey key: String, in container: String) -> Data?
    func write(_ data: Data, forKey key: String, in container: String)
    func remove(forKey key: String, in container: String)
    func removeAll(in container: String)
}

// MARK: - DefaultInMemoryBackingStoreWrapper

public final class DefaultInMemoryBackingStoreWrapper: InMemoryBackingStore, Sendable {
    private static let lock = Lock()
    nonisolated(unsafe) private static var containers = [String: [String: Data]]()
    
    public init() { }
    
    public func read(forKey key: String, in container: String) -> Data? {
        Self.lock.withLock { Self.containers[container]?[key] }
    }
    
    public func write(_ data: Data, forKey key: String, in container: String) {
        _ = Self.lock.withLock { Self.containers[container, default: [:]].updateValue(data, forKey: key) } // old value freed after unlock
    }

    public func remove(forKey key: String, in container: String) {
        _ = Self.lock.withLock { Self.containers[container]?.removeValue(forKey: key) } // old value freed after unlock
    }

    public func removeAll(in container: String) {
        _ = Self.lock.withLock { Self.containers.removeValue(forKey: container) } // old value freed after unlock
    }
}
