//
//  SQLiteStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 15.10.26.
//

import Foundation

// MARK: - SQLiteStorage

/// Values in a SQLite database, one row per key; `clear()` empties the whole database.
public final class SQLiteStorage: KeyValueDataStorage {

    // MARK: Properties

    private let database: any SQLiteDatabase
    private let locator: any SQLiteLocator

    public let scope: Scope

    // MARK: Initializers

    public init(scope: Scope, backingStore: any SQLiteBackingStore, locator: any SQLiteLocator) throws(Error) {
        let databaseURL = try locator.databaseURL(for: scope)
        let protection = Self.fileProtection(for: scope)
        self.database = try Self.execute {
            try backingStore.createDirectory(at: databaseURL.deletingLastPathComponent())
            return try backingStore.open(at: databaseURL, protection: protection)
        }

        self.scope = scope
        self.locator = locator
    }

    public convenience init(scope: Scope) throws(Error) {
        try self.init(scope: scope, backingStore: DefaultSQLiteBackingStoreWrapper(), locator: DefaultSQLiteLocator())
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) throws(Error) -> Data? {
        try Self.execute {
            try database.read(forKey: storedKey(for: key))
        }
    }

    public func save(_ value: Data, forKey key: Key) throws(Error) {
        try Self.execute {
            try database.write(value, forKey: storedKey(for: key))
        }
    }

    public func delete(forKey key: Key) throws(Error) {
        try Self.execute {
            try database.remove(forKey: storedKey(for: key))
        }
    }

    public func clear() throws(Error) {
        try Self.execute {
            try database.removeAll()
        }
    }

    // MARK: Helpers

    private func storedKey(for key: Key) -> String {
        locator.storedKey(forKey: key, in: scope)
    }

    private static func fileProtection(for scope: Scope) -> FileProtectionType? {
        switch scope {
        case let .own(_, protection, _), let .appGroup(_, protection, _):
            protection.fileProtection
        }
    }

    private static func execute<T>(_ body: () throws -> T) throws(Error) -> T {
        do {
            return try body()
        } catch {
            throw Error(error)
        }
    }
}
