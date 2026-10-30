//
//  SQLiteStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - SQLiteStorage + Error

public extension SQLiteStorage {
    enum Error: Swift.Error, Sendable {
        /// Usually the app isn't in the group; also an empty id.
        case groupDirectoryNotFound(String)
        /// The system has no such user directory, the base of `.own` scopes with its retention.
        case directoryNotFound(FileManager.SearchPathDirectory)
        /// Its encoded folder name exceeds 255 bytes.
        case invalidNamespace(Namespace)
        case sqlite(code: Int32, message: String)
        case other(any Swift.Error)
    }
}

// MARK: - Internal

extension SQLiteStorage.Error {
    init(_ error: any Swift.Error) {
        if let error = error as? SQLiteError {
            self = .sqlite(code: error.code, message: error.message)
        } else {
            self = .other(error)
        }
    }
}
