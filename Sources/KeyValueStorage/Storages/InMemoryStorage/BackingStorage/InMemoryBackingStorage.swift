//
//  InMemoryBackingStorage.swift
//  KeyValueStorage
//
//  Created by nsahakyan@servicetitan.com on 17.10.26.
//

import Foundation

// MARK: - InMemoryBackingStorage

public protocol InMemoryBackingStorage {
    func read(forKey key: String, in container: String) -> Data?
    func write(_ data: Data, forKey key: String, in container: String)
    func remove(forKey key: String, in container: String)
    func removeAll(in container: String)
}

// MARK: - InMemoryContainers

public final class InMemoryContainers: InMemoryBackingStorage, @unchecked Sendable {
    public static let shared = InMemoryContainers()
    
    private let lock = Lock()
    private var containers = [String: [String: Data]]()
    
    public init() { }
    
    public func read(forKey key: String, in container: String) -> Data? {
        lock.withLock { containers[container]?[key] }
    }
    
    public func write(_ data: Data, forKey key: String, in container: String) {
        _ = lock.withLock { containers[container, default: [:]].updateValue(data, forKey: key) } // old value freed after unlock
    }

    public func remove(forKey key: String, in container: String) {
        _ = lock.withLock { containers[container]?.removeValue(forKey: key) } // old value freed after unlock
    }

    public func removeAll(in container: String) {
        _ = lock.withLock { containers.removeValue(forKey: container) } // old value freed after unlock
    }
}
