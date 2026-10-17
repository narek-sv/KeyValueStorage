//
//  SQLiteStorage+Error.swift
//  KeyValueStorage
//
//  Created by nsahakyan@servicetitan.com on 16.10.26.
//

// MARK: - SQLiteStorage + Error

public extension SQLiteStorage {
    enum Error: KeyValueDataStorageError {
        case failedToFindGroupDirectory(String)
        case failedToFindDirectory(String)
        case sqlite(code: Int32, message: String)
        case other(Swift.Error)
    }
}
