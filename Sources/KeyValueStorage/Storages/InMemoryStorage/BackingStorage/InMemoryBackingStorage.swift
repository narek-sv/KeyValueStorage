//
//  InMemoryBackingStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import Foundation

// MARK: - InMemoryBackingStorage

/// Named containers of values behind `InMemoryStorage`.
public protocol InMemoryBackingStorage {
    /// The value of `key` in `container`.
    func read(forKey key: String, in container: String) -> Data?

    /// Sets the value of `key` in `container`.
    func write(_ data: Data, forKey key: String, in container: String)

    /// Removes the value of `key` in `container`.
    func remove(forKey key: String, in container: String)

    /// Removes every value in `container`.
    func removeAll(in container: String)
}

// MARK: - InMemoryContainers

/// The live `InMemoryBackingStorage`: lock-protected containers in this process, shared by the storages that use it.
public final class InMemoryContainers: InMemoryBackingStorage, @unchecked Sendable {
    /// The default backing storage.
    public static let shared = InMemoryContainers()

    private let lock = NSLock()
    private var containers = [String: [String: Data]]()

    public init() { }

    public func read(forKey key: String, in container: String) -> Data? {
        withLock { containers[container]?[key] }
    }

    public func write(_ data: Data, forKey key: String, in container: String) {
        withLock { containers[container, default: [:]][key] = data }
    }

    public func remove(forKey key: String, in container: String) {
        withLock { _ = containers[container]?.removeValue(forKey: key) }
    }

    public func removeAll(in container: String) {
        withLock { _ = containers.removeValue(forKey: container) }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
