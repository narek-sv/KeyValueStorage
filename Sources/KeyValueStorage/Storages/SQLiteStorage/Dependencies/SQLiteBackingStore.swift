//
//  SQLiteBackingStore.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import Foundation
import SQLite3

// MARK: - SQLiteBackingStore

public protocol SQLiteBackingStore {
    func createDirectory(at url: URL) throws
    func open(at url: URL, protection: FileProtectionType?) throws -> any SQLiteDatabase
}

// MARK: - SQLiteDatabase

public protocol SQLiteDatabase: AnyObject {
    func read(forKey key: String) throws -> Data?
    func write(_ data: Data, forKey key: String) throws
    func remove(forKey key: String) throws
    func removeAll() throws
}

// MARK: - SQLiteError

public struct SQLiteError: Error, Sendable, Equatable {
    public let code: Int32
    public let message: String

    public init(code: Int32, message: String) {
        self.code = code
        self.message = message
    }
}

// MARK: - DefaultSQLiteBackingStoreWrapper

/// The live SQLite library and file system.
open class DefaultSQLiteBackingStoreWrapper: SQLiteBackingStore {
    private var fileManager: FileManager { .default }

    public init() { }

    open func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(atPath: url.path, withIntermediateDirectories: true)
    }

    open func open(at url: URL, protection: FileProtectionType?) throws -> any SQLiteDatabase {
        try DefaultSQLiteDatabase(url: url, protection: protection)
    }
}

// MARK: - DefaultSQLiteDatabase

final class DefaultSQLiteDatabase: SQLiteDatabase {
    // MARK: Properties

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let database: OpaquePointer
    private let readStatement: OpaquePointer
    private let writeStatement: OpaquePointer
    private let removeStatement: OpaquePointer
    private let removeAllStatement: OpaquePointer

    // MARK: Initializers

    init(url: URL, protection: FileProtectionType?) throws {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX | Self.flag(for: protection)
        let code = sqlite3_open_v2(url.path, &database, flags, nil)
        guard code == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? String(cString: sqlite3_errstr(code))
            sqlite3_close_v2(database)
            throw SQLiteError(code: code, message: message)
        }

        var statements = [OpaquePointer]()
        do {
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
                try statements.append(Self.prepare(sql, in: database))
            }
        } catch {
            statements.forEach { sqlite3_finalize($0) }
            sqlite3_close_v2(database)
            throw error
        }

        self.database = database
        self.readStatement = statements[0]
        self.writeStatement = statements[1]
        self.removeStatement = statements[2]
        self.removeAllStatement = statements[3]
    }

    deinit {
        [readStatement, writeStatement, removeStatement, removeAllStatement].forEach { sqlite3_finalize($0) }
        sqlite3_close_v2(database)
    }

    // MARK: Main Functionality

    func read(forKey key: String) throws -> Data? {
        try run(readStatement) { statement in
            try check(bind(key, to: statement, index: 1))

            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                return try blob(statement, column: 0)
            case SQLITE_DONE:
                return nil
            case let code:
                throw error(code)
            }
        }
    }

    func write(_ data: Data, forKey key: String) throws {
        try run(writeStatement) { statement in
            try check(bind(key, to: statement, index: 1))
            try check(bind(data, to: statement, index: 2))
            try check(sqlite3_step(statement), expected: SQLITE_DONE)
        }
    }

    func remove(forKey key: String) throws {
        try run(removeStatement) { statement in
            try check(bind(key, to: statement, index: 1))
            try check(sqlite3_step(statement), expected: SQLITE_DONE)
        }
    }

    func removeAll() throws {
        try run(removeAllStatement) { statement in
            try check(sqlite3_step(statement), expected: SQLITE_DONE)
        }
    }

    // MARK: Helpers

    private static func flag(for protection: FileProtectionType?) -> Int32 {
        switch protection {
        case FileProtectionType.none?:                                  return SQLITE_OPEN_FILEPROTECTION_NONE
        case FileProtectionType.complete?:                              return SQLITE_OPEN_FILEPROTECTION_COMPLETE
        case FileProtectionType.completeUnlessOpen?:                    return SQLITE_OPEN_FILEPROTECTION_COMPLETEUNLESSOPEN
        case FileProtectionType.completeUntilFirstUserAuthentication?:  return SQLITE_OPEN_FILEPROTECTION_COMPLETEUNTILFIRSTUSERAUTHENTICATION
        default:                                                        return 0
        }
    }

    private func run<T>(_ statement: OpaquePointer, _ body: (OpaquePointer) throws -> T) throws -> T {
        defer {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }

        return try body(statement)
    }

    private func bind(_ key: String, to statement: OpaquePointer, index: Int32) -> Int32 {
        key.utf8CString.withUnsafeBufferPointer { buffer in
            sqlite3_bind_text64(statement, index, buffer.baseAddress, sqlite3_uint64(buffer.count - 1), Self.transient, UInt8(SQLITE_UTF8))
        }
    }

    private func bind(_ value: Data, to statement: OpaquePointer, index: Int32) -> Int32 {
        value.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return sqlite3_bind_zeroblob(statement, index, 0)
            }

            return sqlite3_bind_blob64(statement, index, baseAddress, sqlite3_uint64(bytes.count), Self.transient)
        }
    }

    private func blob(_ statement: OpaquePointer, column: Int32) throws -> Data {
        guard let bytes = sqlite3_column_blob(statement, column) else {
            let code = sqlite3_errcode(database) // NULL also means out of memory
            guard code != SQLITE_NOMEM else {
                throw error(code)
            }

            return Data()
        }

        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }

    private func check(_ code: Int32, expected: Int32 = SQLITE_OK) throws {
        guard code == expected else {
            throw error(code)
        }
    }

    private func error(_ code: Int32) -> SQLiteError {
        SQLiteError(code: code, message: String(cString: sqlite3_errmsg(database)))
    }

    private static func check(_ code: Int32, _ database: OpaquePointer) throws {
        guard code == SQLITE_OK else {
            throw SQLiteError(code: code, message: String(cString: sqlite3_errmsg(database)))
        }
    }

    private static func prepare(_ sql: String, in database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else {
            throw SQLiteError(code: code, message: String(cString: sqlite3_errmsg(database)))
        }

        return statement
    }
}
