//
//  SQLiteStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - SQLiteStorage + Error

public extension SQLiteStorage {
    enum Error: KeyValueDataStorageError {
        /// Usually the app isn't in the group.
        case groupDirectoryNotFound(String)
        case directoryNotFound(FileManager.SearchPathDirectory)
        /// Not a file URL.
        case invalidDirectory(URL)
        /// Its encoded folder name exceeds 255 bytes.
        case invalidNamespace(String)
        case sqlite(code: Int32, message: String)
        case other(Swift.Error)
    }
}
