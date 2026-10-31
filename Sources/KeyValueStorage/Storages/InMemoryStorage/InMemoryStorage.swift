//
//  InMemoryStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - InMemoryStorage

/// Values in the process's memory, shared by every storage of the scope; they last until the process exits.
/// - Note: Thread-safe: an instance can be shared between threads and tasks, but a sequence of operations isn't atomic.
public final class InMemoryStorage: KeyValueDataStorage, Sendable {

    // MARK: Properties

    private let backingStore: any InMemoryBackingStore
    private let locator: any InMemoryLocator
    private let bucket: String

    public let scope: Scope

    // MARK: Initializers

    public init(scope: Scope, backingStore: any InMemoryBackingStore, locator: any InMemoryLocator) {
        self.bucket = locator.bucket(for: scope)
        self.scope = scope
        self.backingStore = backingStore
        self.locator = locator
    }

    public convenience init(scope: Scope) {
        self.init(scope: scope, backingStore: DefaultInMemoryBackingStoreWrapper(), locator: DefaultInMemoryLocator())
    }

    public convenience init() {
        self.init(scope: .default)
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) -> Data? {
        backingStore.read(forKey: storedKey(for: key), in: bucket)
    }

    public func save(_ value: Data, forKey key: Key) {
        backingStore.write(value, forKey: storedKey(for: key), in: bucket)
    }

    public func delete(forKey key: Key) {
        backingStore.remove(forKey: storedKey(for: key), in: bucket)
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

    // MARK: Helpers

    private func storedKey(for key: Key) -> String {
        locator.storedKey(forKey: key, in: scope)
    }
}
