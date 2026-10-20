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

    private static let maximumKeyLength = 128
    private static let maximumValueSize = 1024 * 1024

    private let storage: any UbiquitousBackingStore
    private let keyPrefix: String?
    public let scope: Scope

    // MARK: Initializers

    public init(scope: Scope, backingStorage: any UbiquitousBackingStore) {
        switch scope {
        case let .shared(container):
            self.keyPrefix = container.map(KeyNamespace.prefix(for:))
        }

        self.scope = scope
        self.storage = backingStorage
    }

    public convenience init(scope: Scope) {
        self.init(scope: scope, backingStorage: DefaultUbiquitousBackingStoreWrapper())
    }

    public convenience init() {
        self.init(scope: .default)
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) throws -> Data? {
        try storage.read(forKey: storedKey(for: key))
    }

    public func save(_ value: Data, forKey key: Key) throws {
        let storedKey = try storedKey(for: key)
        guard value.count <= Self.maximumValueSize else {
            throw Error.valueTooLarge(key: key, size: value.count)
        }

        storage.write(value, forKey: storedKey)
    }

    public func delete(forKey key: Key) throws {
        try storage.remove(forKey: storedKey(for: key))
    }

    public func clear() {
        for key in storage.keys() where keyPrefix.map({ key.hasPrefix($0) }) ?? true {
            storage.remove(forKey: key)
        }
    }

    @discardableResult
    public func synchronize() -> Bool {
        storage.synchronize()
    }

    // MARK: Helpers

    private func storedKey(for key: Key) throws -> String {
        let storedKey = keyPrefix.map { $0 + key } ?? key
        guard storedKey.utf16.count <= Self.maximumKeyLength else {
            throw Error.invalidKey(key)
        }

        return storedKey
    }
}
