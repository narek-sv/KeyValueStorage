//
//  FileStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - FileStorage + Error

public extension FileStorage {
    enum Error: Swift.Error, Sendable {
        /// Usually the app isn't in the group; also an empty id.
        case groupDirectoryNotFound(String)
        case directoryNotFound(FileManager.SearchPathDirectory)
        /// Its encoded folder name exceeds 255 bytes.
        case invalidNamespace(Namespace)
        /// Its encoded file name exceeds 255 bytes.
        case invalidKey(Key)
        /// Something that isn't the scope's is at the key's file or the scope's folder; it's never removed.
        case pathOccupied(URL)
        /// `EPERM`: the file is protected while the device is locked, or the sandbox denied access.
        case protectedDataUnavailable
        case other(Swift.Error)
    }
}
