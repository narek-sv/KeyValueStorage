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
