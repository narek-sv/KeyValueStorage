//
//  SQLiteStorage.swift
//
//
//  Created by Narek Sahakyan on 15.10.26.
//

import Foundation

// MARK: - SQLiteStorage

public final class SQLiteStorage: KeyValueDataStorage {

    // MARK: Properties

    static let databaseName = "KeyValueStorage.sqlite"
    static let directoryPrefixName = "SQLite"

    private let database: any SQLiteDatabase
    public let domain: Domain

    // MARK: Initializers

    public init(domain: Domain, backingStorage: any SQLiteBackingStore) throws {
        let root = try Self.root(for: domain, resolver: backingStorage)
        let protection = Self.fileProtection(for: domain)
        self.database = try Self.execute {
            try backingStorage.createDirectory(at: root)
            return try backingStorage.open(at: root.appendingPathComponent(Self.databaseName, isDirectory: false), protection: protection)
        }

        self.domain = domain
    }

    public convenience init(domain: Domain) throws {
        try self.init(domain: domain, backingStorage: DefaultSQLiteBackingStoreWrapper())
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) throws -> Data? {
        try Self.execute {
            try database.read(forKey: key)
        }
    }

    public func save(_ value: Data, forKey key: Key) throws {
        try Self.execute {
            try database.write(value, forKey: key)
        }
    }

    public func delete(forKey key: Key) throws {
        try Self.execute {
            try database.remove(forKey: key)
        }
    }

    public func clear() throws {
        try Self.execute {
            try database.removeAll()
        }
    }

    // MARK: Helpers

    private static func root(for domain: Domain, resolver: any StorageDirectoryResolving) throws -> URL {
        let directory: StorageDirectory
        switch domain {
        case let .app(.applicationSupport(container), _):   directory = .applicationSupport(container: container)
        case let .app(.cache(container), _):                directory = .cache(container: container)
        case let .app(.documents(container), _):            directory = .documents(container: container)
        case let .app(.temporary(container), _):            directory = .temporary(container: container)
        case let .appGroup(groupId, container, _):          directory = .appGroup(groupId: groupId, container: container)
        }

        do {
            return try directory.url(storageFolder: directoryPrefixName, resolver: resolver)
        } catch StorageDirectory.Failure.directoryNotFound(let name) {
            throw Error.failedToFindDirectory(name)
        } catch StorageDirectory.Failure.groupNotFound(let groupId) {
            throw Error.failedToFindGroupDirectory(groupId)
        }
    }

    private static func fileProtection(for domain: Domain) -> FileProtectionType? {
        let protection: Protection
        switch domain {
        case let .app(_, value), let .appGroup(_, _, value):
            protection = value
        }

        switch protection {
        case .inherited:                            return nil
        case .none:                                 return FileProtectionType.none
        case .complete:                             return .complete
        case .completeUnlessOpen:                   return .completeUnlessOpen
        case .completeUntilFirstUserAuthentication: return .completeUntilFirstUserAuthentication
        }
    }

    private static func convert(error: Swift.Error) -> Error {
        if let error = error as? SQLiteError {
            return .sqlite(code: error.code, message: error.message)
        }

        return .other(error)
    }

    @discardableResult
    private static func execute<T>(_ block: () throws -> T) rethrows -> T {
        do {
            return try block()
        } catch {
            throw convert(error: error)
        }
    }
}
