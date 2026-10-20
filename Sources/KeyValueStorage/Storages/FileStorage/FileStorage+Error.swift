//
//  FileStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - FileStorage + Error

public extension FileStorage {
    /// The errors a `FileStorage` throws.
    enum Error: KeyValueDataStorageError {
        /// The system has no container for this App Group ID, usually because the app isn't in the group.
        case groupDirectoryNotFound(String)
        /// The system returned no such base directory; the value is its name, such as `Documents`.
        case directoryNotFound(String)
        /// The URL of `AppScope.directory(at:)` isn't a file URL.
        case invalidDirectory(URL)
        /// The key is empty, `.` or `..`, contains `/` or NUL, or its encoded file name exceeds 255 bytes.
        case invalidKey(String)
        /// Reading or writing failed with `EPERM`: the file is protected while locked, or the sandbox denied access.
        case protectedDataUnavailable
        /// Any other file system error.
        case other(Swift.Error)
    }
}
