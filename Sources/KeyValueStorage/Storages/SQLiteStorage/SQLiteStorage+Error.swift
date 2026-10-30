//
//  SQLiteStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - SQLiteStorage + Error

public extension SQLiteStorage {
    /// The errors a `SQLiteStorage` throws.
    enum Error: Swift.Error, Sendable {
        /// The system has no container for the App Group: usually the app isn't in the group, or the id is empty.
        case groupDirectoryNotFound(String)
        /// The system has no such user directory, the base of `.own` scopes of its retention.
        case directoryNotFound(FileManager.SearchPathDirectory)
        /// Its encoded folder name is over 255 bytes.
        case invalidNamespace(Namespace)
        /// A SQLite result code and its message, such as `SQLITE_CORRUPT` for a damaged database, or `SQLITE_BUSY` after
        /// waiting a second for another process.
        case sqlite(code: Int32, message: String)
        /// Creating the database's folder failed, with the original error.
        case other(any Swift.Error)
    }
}

// MARK: - Internal

extension SQLiteStorage.Error {
    /// The error for a failed SQLite call.
    init(_ error: SQLiteError) {
        self = .sqlite(code: error.code, message: error.message)
    }
}
