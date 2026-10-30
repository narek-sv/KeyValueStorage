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
        /// The system has no such user directory, the base of `.own` scopes with its retention.
        case directoryNotFound(FileManager.SearchPathDirectory)
        /// Its encoded folder name exceeds 255 bytes.
        case invalidNamespace(Namespace)
        /// Its encoded file name exceeds 255 bytes.
        case invalidKey(Key)
        /// Something that isn't the scope's is at the key's file or the scope's folder; it's never removed.
        case pathOccupied(URL)
        /// `EPERM`: the file is protected while the device is locked, or the sandbox denied access.
        case protectedDataUnavailable
        case other(any Swift.Error)
    }
}

// MARK: - Internal

extension FileStorage.Error {
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
