//
//  SQLiteStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 15.10.26.
//

import Foundation

// MARK: - SQLiteStorage

/// Values in a SQLite database, one row per key; `clear()` empties the whole database.
/// - Note: Thread-safe: an instance can be shared between threads and tasks, but a sequence of operations isn't atomic.
///   Calls on one instance wait for each other, blocking their threads; wrap it in `IsolatedKeyValueDataStorage` to have them suspend instead.
public final class SQLiteStorage: KeyValueDataStorage, Sendable {

    // MARK: Properties

    private let database: any SQLiteDatabase
    private let locator: any SQLiteLocator

    public let scope: Scope

    // MARK: Initializers

    public init(scope: Scope, backingStore: any SQLiteBackingStore, locator: any SQLiteLocator) throws(Error) {
        let databaseURL = try locator.databaseURL(for: scope)
        let protection = Self.fileProtection(for: scope)
        do {
            try backingStore.createDirectory(at: databaseURL.deletingLastPathComponent())
        } catch {
            throw .other(error)
        }

        self.database = try Self.execute { () throws(SQLiteError) in
            try backingStore.open(at: databaseURL, protection: protection)
        }

        self.scope = scope
        self.locator = locator
    }

    public convenience init(scope: Scope) throws(Error) {
        try self.init(scope: scope, backingStore: DefaultSQLiteBackingStoreWrapper(), locator: DefaultSQLiteLocator())
    }

    public convenience init() throws(Error) {
        try self.init(scope: .default)
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) throws(Error) -> Data? {
        try Self.execute { () throws(SQLiteError) in
            try database.read(forKey: storedKey(for: key))
        }
    }

    public func save(_ value: Data, forKey key: Key) throws(Error) {
        try Self.execute { () throws(SQLiteError) in
            try database.write(value, forKey: storedKey(for: key))
        }
    }

    public func delete(forKey key: Key) throws(Error) {
        try Self.execute { () throws(SQLiteError) in
            try database.remove(forKey: storedKey(for: key))
        }
    }

    public func clear() throws(Error) {
        try Self.execute { () throws(SQLiteError) in
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

    private static func execute<T>(_ body: () throws(SQLiteError) -> T) throws(Error) -> T {
        do throws(SQLiteError) {
            return try body()
        } catch {
            throw Error(error)
        }
    }
}
