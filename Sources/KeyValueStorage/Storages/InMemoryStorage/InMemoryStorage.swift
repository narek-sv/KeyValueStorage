//
//  InMemoryStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - InMemoryStorage

public final class InMemoryStorage: KeyValueDataStorage {

    // MARK: Properties

    private let backingStore: any InMemoryBackingStore
    private let bucket: String?
    public let scope: Scope

    // MARK: Initializers

    public init(scope: Scope, backingStore: any InMemoryBackingStore) {
        switch scope {
        case .app(nil):
            self.bucket = nil
        case let .app(.bucket(name)?):
            self.bucket = name
        }

        self.scope = scope
        self.backingStore = backingStore
    }

    public convenience init(scope: Scope) {
        self.init(scope: scope, backingStore: DefaultInMemoryBackingStoreWrapper())
    }

    public convenience init() {
        self.init(scope: .default)
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) -> Data? {
        backingStore.read(forKey: key, in: bucket)
    }

    public func save(_ value: Data, forKey key: Key) {
        backingStore.write(value, forKey: key, in: bucket)
    }

    public func delete(forKey key: Key) {
        backingStore.remove(forKey: key, in: bucket)
    }

    public func set(_ value: Data?, forKey key: Key) {
        if let value {
            save(value, forKey: key)
        } else {
            delete(forKey: key)
        }
    }

    public func clear() {
        backingStore.removeAll(in: bucket)
    }
}
