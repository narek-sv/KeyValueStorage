//
//  InMemoryStorage.swift
//
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - InMemoryStorage

public final class InMemoryStorage: KeyValueDataStorage {

    public static var defaultBackingStorage: any InMemoryBackingStorage {
        InMemoryContainers.shared
    }

    // MARK: Properties

    private let storage: any InMemoryBackingStorage
    private let container: Container
    public let domain: Domain

    // MARK: Initializers

    /// Uses the domain's container.
    public init(domain: Domain, backingStorage: any InMemoryBackingStorage) {
        switch domain {
        case let .app(container):
            self.container = container
        }

        self.domain = domain
        self.storage = backingStorage
    }

    public convenience init(domain: Domain = .default) {
        self.init(domain: domain, backingStorage: Self.defaultBackingStorage)
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) -> Data? {
        storage.read(forKey: key, in: container)
    }

    public func save(_ value: Data, forKey key: Key) {
        storage.write(value, forKey: key, in: container)
    }

    public func delete(forKey key: Key) {
        storage.remove(forKey: key, in: container)
    }

    public func clear() {
        storage.removeAll(in: container)
    }
}
