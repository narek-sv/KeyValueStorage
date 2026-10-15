//
//  SQLiteStorage.swift
//
//
//  Created by Narek Sahakyan on 15.10.26.
//

import Foundation
import SQLite3

// MARK: - Data Storage

@SQLiteActor
open class SQLiteStorage: KeyValueDataStorage, @unchecked Sendable {
    
    // MARK: Properties
    
    private let connection: Connection
    public let domain: Domain?
    
    // MARK: Initializers
    
    /// Stores values in `Application Support/<bundle identifier>/KeyValueStorage/SQLite/KeyValueStorage.sqlite`.
    /// The folder is separate from the other storages' folders, so clearing one storage never touches the database.
    public required init() throws {
        let fileManager = FileManager.default
        guard let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw Error.failedToFindApplicationSupportDirectory
        }
        
        let root = url
            .appendingPathComponent(Self.defaultGroup, isDirectory: true)
            .appendingPathComponent(Self.libraryDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.directoryName, isDirectory: true)
        self.connection = try Self.open(root: root, fileManager: fileManager)
        self.domain = nil
    }
    
    /// Stores values in `<app group container>/KeyValueStorage/SQLite/KeyValueStorage.sqlite`.
    /// The path doesn't depend on the bundle identifier, so the app and its extensions share the same database.
    public required init(domain: Domain) throws {
        let fileManager = FileManager.default
        guard let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: domain) else {
            throw Error.failedToInitSharedDirectory
        }
        
        let root = url
            .appendingPathComponent(Self.libraryDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.directoryName, isDirectory: true)
        self.connection = try Self.open(root: root, fileManager: fileManager)
        self.domain = domain
    }
    
    /// Stores values in `<root>/KeyValueStorage.sqlite`.
    public init(fileManager: FileManager, root: URL) throws {
        self.connection = try Self.open(root: root, fileManager: fileManager)
        self.domain = nil
    }
    
    // MARK: Main Functionality
    
    public func fetch(forKey key: Key) throws -> Data? {
        try execute {
            try connection.run(connection.fetch) { statement in
                try connection.check(connection.bind(key, to: statement, index: 1))
                
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    return connection.blob(statement, column: 0)
                case SQLITE_DONE:
                    return nil
                case let code:
                    throw connection.error(code)
                }
            }
        }
    }
    
    public func save(_ value: Data, forKey key: Key) throws {
        try execute {
            try connection.run(connection.save) { statement in
                try connection.check(connection.bind(key, to: statement, index: 1))
                try connection.check(connection.bind(value, to: statement, index: 2))
                try connection.check(sqlite3_step(statement), expected: SQLITE_DONE)
            }
        }
    }
    
    public func delete(forKey key: Key) throws {
        try execute {
            try connection.run(connection.delete) { statement in
                try connection.check(connection.bind(key, to: statement, index: 1))
                try connection.check(sqlite3_step(statement), expected: SQLITE_DONE)
            }
        }
    }
    
    public func set(_ value: Data?, forKey key: Key) throws {
        if let value = value {
            try save(value, forKey: key)
        } else {
            try delete(forKey: key)
        }
    }
    
    public func clear() throws {
        try execute {
            try connection.run(connection.clear) { statement in
                try connection.check(sqlite3_step(statement), expected: SQLITE_DONE)
            }
        }
    }
    
    // MARK: Helpers
    
    private static func open(root: URL, fileManager: FileManager) throws -> Connection {
        do {
            try fileManager.createDirectory(atPath: root.path, withIntermediateDirectories: true)
            return try Connection(url: root.appendingPathComponent(Self.databaseName, isDirectory: false))
        } catch let error as Error {
            throw error
        } catch {
            throw Error.other(error)
        }
    }
    
    private func convert(error: Swift.Error) -> Error {
        if let error = error as? SQLiteStorage.Error {
            return error
        }
        
        return .other(error)
    }
    
    @discardableResult
    private func execute<T>(_ block: () throws -> T) rethrows -> T {
        do {
            return try block()
        } catch {
            throw convert(error: error)
        }
    }
}

// MARK: - Associated Types

public extension SQLiteStorage {
    /// The name of the folder in `KeyValueStorage` that holds the database.
    nonisolated static let directoryName = "SQLite"
    
    /// The name of the database file.
    nonisolated static let databaseName = "KeyValueStorage.sqlite"
    
    typealias Key = String
    typealias Domain = String
    
    enum Error: KeyValueDataStorageError {
        case failedToInitSharedDirectory
        case failedToFindApplicationSupportDirectory
        case sqlite(code: Int32, message: String)
        case other(Swift.Error)
    }
}

// MARK: - Connection

/// An open database with its prepared statements, closed when the storage is released.
private final class Connection: @unchecked Sendable {
    static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    private let database: OpaquePointer
    let fetch: OpaquePointer
    let save: OpaquePointer
    let delete: OpaquePointer
    let clear: OpaquePointer
    
    init(url: URL) throws {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(url.path, &database, flags, nil)
        guard code == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? String(cString: sqlite3_errstr(code))
            sqlite3_close_v2(database)
            throw SQLiteStorage.Error.sqlite(code: code, message: message)
        }
        
        var statements = [OpaquePointer]()
        do {
            // An app and its extensions may use the database at the same time: in WAL mode readers don't block the writer,
            // and the busy timeout makes a write wait for another process's write instead of failing
            sqlite3_busy_timeout(database, 1000)
            try Self.check(sqlite3_exec(database, "PRAGMA journal_mode = WAL", nil, nil, nil), database)
            try Self.check(sqlite3_exec(database, """
                CREATE TABLE IF NOT EXISTS KeyValueStorage (key TEXT PRIMARY KEY NOT NULL, value BLOB NOT NULL) WITHOUT ROWID
                """, nil, nil, nil), database)
            
            for sql in [
                "SELECT value FROM KeyValueStorage WHERE key = ?",
                "INSERT OR REPLACE INTO KeyValueStorage (key, value) VALUES (?, ?)",
                "DELETE FROM KeyValueStorage WHERE key = ?",
                "DELETE FROM KeyValueStorage"
            ] {
                var statement: OpaquePointer?
                try Self.check(sqlite3_prepare_v2(database, sql, -1, &statement, nil), database)
                statements.append(statement!)
            }
        } catch {
            statements.forEach { sqlite3_finalize($0) }
            sqlite3_close_v2(database)
            throw error
        }
        
        self.database = database
        self.fetch = statements[0]
        self.save = statements[1]
        self.delete = statements[2]
        self.clear = statements[3]
    }
    
    deinit {
        [fetch, save, delete, clear].forEach { sqlite3_finalize($0) }
        sqlite3_close_v2(database)
    }
    
    /// Runs a prepared statement and resets it afterwards, so it can be reused.
    func run<T>(_ statement: OpaquePointer, _ body: (OpaquePointer) throws -> T) throws -> T {
        defer {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        
        return try body(statement)
    }
    
    /// Binds the whole UTF-8 representation, so keys containing a NUL character stay distinct.
    func bind(_ key: String, to statement: OpaquePointer, index: Int32) -> Int32 {
        key.utf8CString.withUnsafeBufferPointer { buffer in
            // The buffer always ends with a NUL terminator, which isn't part of the key
            sqlite3_bind_text64(statement, index, buffer.baseAddress, sqlite3_uint64(buffer.count - 1), Self.transient, UInt8(SQLITE_UTF8))
        }
    }
    
    func bind(_ value: Data, to statement: OpaquePointer, index: Int32) -> Int32 {
        value.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                // A nil pointer would bind NULL, which the column doesn't allow
                return sqlite3_bind_zeroblob(statement, index, 0)
            }
            
            return sqlite3_bind_blob64(statement, index, baseAddress, sqlite3_uint64(bytes.count), Self.transient)
        }
    }
    
    func blob(_ statement: OpaquePointer, column: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(statement, column) else {
            return Data()
        }
        
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
    
    func check(_ code: Int32, expected: Int32 = SQLITE_OK) throws {
        guard code == expected else {
            throw error(code)
        }
    }
    
    func error(_ code: Int32) -> SQLiteStorage.Error {
        .sqlite(code: code, message: String(cString: sqlite3_errmsg(database)))
    }
    
    private static func check(_ code: Int32, _ database: OpaquePointer) throws {
        guard code == SQLITE_OK else {
            throw SQLiteStorage.Error.sqlite(code: code, message: String(cString: sqlite3_errmsg(database)))
        }
    }
}

// MARK: - Global Actors

@globalActor
public final class SQLiteActor {
    public actor Actor { }
    public static let shared = Actor()
}
