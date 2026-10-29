//
//  UserDefaultsStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - UserDefaultsStorage

public final class UserDefaultsStorage: KeyValueDataStorage {

    // MARK: Properties

    private let suite: any UserDefaultsSuite
    private let locator: any UserDefaultsLocator
    public let scope: Scope

    // MARK: Initializers

    public init(scope: Scope, backingStore: any UserDefaultsBackingStore, locator: any UserDefaultsLocator) throws(Error) {
        switch locator.suite(for: scope) {
        case .standard:
            self.suite = backingStore.standard
        case let .suite(name):
            guard let suite = backingStore.suite(named: name) else {
                throw .invalidSuiteName(name)
            }

            self.suite = suite
        }

        self.scope = scope
        self.locator = locator
    }

    public convenience init(scope: Scope) throws(Error) {
        try self.init(scope: scope, backingStore: DefaultUserDefaultsBackingStoreWrapper(), locator: DefaultUserDefaultsLocator())
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) -> Data? {
        suite.read(forKey: storedKey(for: key)) as? Data
    }

    public func save(_ value: Data, forKey key: Key) throws(Error) {
        let storedKey = storedKey(for: key)
        if let object = suite.read(forKey: storedKey), !(object is Data) {
            throw .keyOccupied(storedKey)
        }

        suite.write(value, forKey: storedKey)
    }

    public func delete(forKey key: Key) {
        removeValue(forStoredKey: storedKey(for: key))
    }

    public func clear() {
        for storedKey in suite.keys() where isValueKey(storedKey) {
            removeValue(forStoredKey: storedKey)
        }
    }

    // MARK: Helpers

    private func storedKey(for key: Key) -> String {
        locator.storedKey(forKey: key, in: scope)
    }

    /// Never a value of another type: it isn't the scope's.
    private func removeValue(forStoredKey storedKey: String) {
        guard suite.read(forKey: storedKey) is Data else {
            return
        }

        suite.remove(forKey: storedKey)
    }

    private func isValueKey(_ storedKey: String) -> Bool {
        guard let key = locator.key(forStoredKey: storedKey, in: scope) else {
            return false
        }

        // Bytes, not `==`: the suite tells canonically equal keys apart
        return locator.storedKey(forKey: key, in: scope).utf8.elementsEqual(storedKey.utf8)
    }
}
