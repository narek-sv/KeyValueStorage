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

    private static let databaseName = ".\(Scope.defaultName).sqlite"

    private let database: any SQLiteDatabase
    public let scope: Scope

    // MARK: Initializers

    public init(scope: Scope, backingStore: any SQLiteBackingStore) throws(Error) {
        let root = try Self.root(for: scope, resolver: backingStore)
        let protection = Self.fileProtection(for: scope)
        self.database = try Self.execute {
            try backingStore.createDirectory(at: root)
            return try backingStore.open(at: root.appendingPathComponent(Self.databaseName, isDirectory: false), protection: protection)
        }

        self.scope = scope
    }

    public convenience init(scope: Scope) throws(Error) {
        try self.init(scope: scope, backingStore: DefaultSQLiteBackingStoreWrapper())
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) throws(Error) -> Data? {
        try Self.execute {
            try database.read(forKey: key)
        }
    }

    public func save(_ value: Data, forKey key: Key) throws(Error) {
        try Self.execute {
            try database.write(value, forKey: key)
        }
    }

    public func delete(forKey key: Key) throws(Error) {
        try Self.execute {
            try database.remove(forKey: key)
        }
    }

    public func clear() throws(Error) {
        try Self.execute {
            try database.removeAll()
        }
    }

    // MARK: Helpers

    private static func root(for scope: Scope, resolver: any StorageDirectoryResolving) throws(Error) -> URL {
        let directory: StorageDirectory
        switch scope {
        case .app(.applicationSupport, _, _):   directory = .applicationSupport
        case .app(.cache, _, _):                directory = .cache
        case .app(.documents, _, _):            directory = .documents
        case .app(.temporary, _, _):            directory = .temporary
        case let .app(.directory(url), _, _):   directory = .directory(at: url)
        case let .appGroup(groupId, _, _):      directory = .appGroup(groupId: groupId)
        }

        let namespace: String?
        switch scope.namespace {
        case let .directory(name)?: namespace = name
        case nil:                   namespace = nil
        }

        do throws(StorageDirectory.Failure) {
            return try directory.url(namespace: namespace, resolver: resolver)
        } catch {
            switch error {
            case let .directoryNotFound(name):  throw .failedToFindDirectory(name)
            case let .groupNotFound(groupId):   throw .failedToFindGroupDirectory(groupId)
            case let .invalidDirectory(url):    throw .invalidDirectory(url)
            }
        }
    }

    private static func fileProtection(for scope: Scope) -> FileProtectionType? {
        let protection: Protection
        switch scope {
        case let .app(_, _, value), let .appGroup(_, _, value):
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
    private static func execute<T>(_ block: () throws -> T) throws(Error) -> T {
        do {
            return try block()
        } catch {
            throw convert(error: error)
        }
    }
}
