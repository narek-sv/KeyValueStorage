//
//  SQLiteStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - SQLiteStorage + Error

public extension SQLiteStorage {
    /// The errors an `SQLiteStorage` throws.
    enum Error: KeyValueDataStorageError {
        /// The system has no container for this App Group ID, usually because the app isn't in the group.
        case failedToFindGroupDirectory(String)
        /// The system returned no such base directory; the value is its name, such as `Documents`.
        case failedToFindDirectory(String)
        /// The URL of `AppScope.directory(at:)` isn't a file URL.
        case invalidDirectory(URL)
        /// An SQLite error, with its result code and message.
        case sqlite(code: Int32, message: String)
        /// Any other error, such as a failure to create the database's directory.
        case other(Swift.Error)
    }
}
