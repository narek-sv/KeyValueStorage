//
//  InMemoryStorage.swift
//
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - InMemoryStorage

public final class InMemoryStorage: KeyValueDataStorage {

    // MARK: Properties

    private let storage: any InMemoryBackingStore
    private let container: Container
    public let domain: Domain

    // MARK: Initializers

    public init(domain: Domain, backingStorage: any InMemoryBackingStore) {
        switch domain {
        case let .app(container):
            self.container = container
        }

        self.domain = domain
        self.storage = backingStorage
    }

    public convenience init(domain: Domain) {
        self.init(domain: domain, backingStorage: DefaultInMemoryBackingStoreWrapper())
    }

    public convenience init() {
        self.init(domain: .default)
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

    public func set(_ value: Data?, forKey key: Key) {
        if let value {
            save(value, forKey: key)
        } else {
            delete(forKey: key)
        }
    }

    public func clear() {
        storage.removeAll(in: container)
    }
}
