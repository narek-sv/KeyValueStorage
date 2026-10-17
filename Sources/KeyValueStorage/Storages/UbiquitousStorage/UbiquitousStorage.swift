//
//  UbiquitousStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import Foundation

// MARK: - UbiquitousStorage

/// The iCloud key-value store, synced across the person's devices: for small, non-secret values.
/// It holds 1024 keys and 1 MB per store; exceeding the total fails silently.
@available(watchOS 9.0, *)
public final class UbiquitousStorage: KeyValueDataStorage {
    /// The longest key in UTF-16 units; longer keys raise an exception.
    static let maximumKeyLength = 128

    /// The largest value in bytes.
    static let maximumValueSize = 1024 * 1024

    public static var defaultBackingStorage: any UbiquitousBackingStorage {
        DefaultUbiquitousBackingStorage()
    }

    // MARK: Properties

    private let storage: any UbiquitousBackingStorage
    /// `<container>/`, or `nil` for raw keys.
    private let keyPrefix: String?
    public let domain: Domain

    // MARK: Initializers

    /// Uses the domain's container.
    public init(domain: Domain, backingStorage: any UbiquitousBackingStorage) {
        switch domain {
        case let .shared(container):
            self.keyPrefix = container.map(KeyNamespace.prefix(for:))
        }

        self.domain = domain
        self.storage = backingStorage
    }

    public convenience init(domain: Domain = .default) {
        self.init(domain: domain, backingStorage: Self.defaultBackingStorage)
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

    /// Removes the container's values, or the whole store for a `nil` container, on every device.
    public func clear() {
        for key in storage.keys() where keyPrefix.map({ key.hasPrefix($0) }) ?? true {
            storage.remove(forKey: key)
        }
    }

    /// Syncs in-memory values with iCloud, which the system also does on its own; `false` on error, such as a missing entitlement.
    @discardableResult
    public func synchronize() -> Bool {
        storage.synchronize()
    }

    // MARK: Helpers

    /// The prefixed key, checked against the store's length limit.
    private func storedKey(for key: Key) throws -> String {
        let storedKey = keyPrefix.map { $0 + key } ?? key
        guard storedKey.utf16.count <= Self.maximumKeyLength else {
            throw Error.invalidKey(key)
        }

        return storedKey
    }
}
