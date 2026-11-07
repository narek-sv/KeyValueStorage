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
    enum Error: Swift.Error, Sendable {
        /// The system has no container for the App Group: usually the app isn't in the group, or the id is empty.
        case groupDirectoryNotFound(String)
        /// The system has no such user directory, the base of `.own` scopes of its retention.
        case directoryNotFound(FileManager.SearchPathDirectory)
        /// Its encoded folder name is over 255 bytes.
        case invalidNamespace(Namespace)
        /// Its encoded file name is over 255 bytes.
        /// - Note: The system also refuses a whole path over 1024 bytes, which only a deep App Group container or home
        ///   folder reaches: every operation on the key then throws `.other`.
        case invalidKey(Key)
        /// Something that isn't a value is at the key's file, or isn't a folder where the scope's folder goes, and `save`
        /// never replaces it.
        case pathOccupied(URL)
        /// `EPERM`: the file is protected while the device is locked, or the sandbox denied access, which unlocking doesn't fix.
        case protectedDataUnavailable
        /// Any other file system failure, with the original error.
        case other(any Swift.Error)
    }
}

// MARK: - Internal

extension FileStorage.Error {
    /// The error for a failed item lookup.
    init(_ error: FileItemError) {
        switch error {
        case .notPermitted: self = .protectedDataUnavailable
        default:            self = .other(error)
        }
    }

    /// The error for a failed file system call.
    init(_ error: any Swift.Error) {
        let nsError = error as NSError
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError

        if nsError.domain == NSCocoaErrorDomain,
           [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(nsError.code),
           underlying?.domain == NSPOSIXErrorDomain, underlying?.code == Int(EPERM) {
            self = .protectedDataUnavailable
        } else {
            self = .other(error)
        }
    }
}
