//
//  UbiquitousStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import Foundation

// MARK: - UbiquitousStorage

@available(watchOS 9.0, *)
public final class UbiquitousStorage: KeyValueDataStorage {

    // MARK: Properties

    private static let maximumValueSize = 1024 * 1024

    private let backingStore: any UbiquitousBackingStore
    private let locator: any UbiquitousLocator
    public let scope: Scope

    // MARK: Initializers

    public init(scope: Scope, backingStore: any UbiquitousBackingStore, locator: any UbiquitousLocator) {
        self.scope = scope
        self.backingStore = backingStore
        self.locator = locator
    }

    public convenience init(scope: Scope) {
        self.init(scope: scope, backingStore: DefaultUbiquitousBackingStoreWrapper(), locator: DefaultUbiquitousLocator())
    }

    public convenience init() {
        self.init(scope: .default)
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) throws(Error) -> Data? {
        try backingStore.read(forKey: storedKey(for: key))
    }

    public func save(_ value: Data, forKey key: Key) throws(Error) {
        let storedKey = try storedKey(for: key)
        guard value.count <= Self.maximumValueSize else {
            throw Error.valueTooLarge(key: key, size: value.count)
        }

        backingStore.write(value, forKey: storedKey)
    }

    public func delete(forKey key: Key) throws(Error) {
        try backingStore.remove(forKey: storedKey(for: key))
    }

    public func clear() {
        for storedKey in backingStore.keys() where isValueKey(storedKey) {
            backingStore.remove(forKey: storedKey)
        }
    }

    @discardableResult
    public func synchronize() -> Bool {
        backingStore.synchronize()
    }

    // MARK: Helpers

    private func storedKey(for key: Key) throws(Error) -> String {
        try locator.storedKey(forKey: key, in: scope)
    }

    private func isValueKey(_ storedKey: String) -> Bool {
        guard let key = locator.key(forStoredKey: storedKey, in: scope) else {
            return false
        }

        return (try? locator.storedKey(forKey: key, in: scope)) == storedKey
    }
}
