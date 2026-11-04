//
//  FileBackingStore.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - FileBackingStore

/// One system call per member, without rules: the storage owns them.
public protocol FileBackingStore: Sendable {
    /// `lstat`, which describes a link itself.
    func itemType(at url: URL) throws(FileItemError) -> FileAttributeType
    /// `Data(contentsOf:)`.
    func read(at url: URL) throws -> Data
    /// `Data.write(to:options:)`.
    func write(_ data: Data, at url: URL, options: Data.WritingOptions) throws
    /// `unlink`, which removes a file, or a link but never what it points to, and never a folder.
    func remove(at url: URL) throws(FileItemError)
    /// `FileManager.createDirectory(at:withIntermediateDirectories: true)`.
    func createDirectory(at url: URL) throws
    /// `URL.setResourceValues(_:)` with `isExcludedFromBackup`, which on a folder covers everything inside.
    func excludeFromBackup(at url: URL) throws
    /// `FileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor:create: true)`: a new
    /// temporary folder on the volume of `url`.
    func itemReplacementDirectory(appropriateFor url: URL) throws -> URL
    /// `rename`, which moves an item in one step within its volume, and a link but never what it points to.
    func move(at url: URL, to destination: URL) throws(FileItemError)
    /// `FileManager.removeItem(at:)` on a background queue, ignoring failures.
    /// - Warning: Removes a folder with everything inside.
    func removeInBackground(at url: URL)
}

// MARK: - DefaultFileBackingStoreWrapper

/// The live file system.
/// - Warning: Subclasses inherit `Sendable`: their own state must be thread-safe too.
open class DefaultFileBackingStoreWrapper: FileBackingStore, @unchecked Sendable {
    private var fileManager: FileManager { .default }

    public init() { }

    open func itemType(at url: URL) throws(FileItemError) -> FileAttributeType {
        var status = stat()
        // Foundation's path encoding, as its reads and writes use; `nil` for a URL without a file system path
        let code = url.withUnsafeFileSystemRepresentation { path in
            path.map { lstat($0, &status) == 0 ? 0 : errno }
        } ?? EINVAL
        guard code == 0 else {
            throw FileItemError(code: code)
        }

        return FileAttributeType(mode: status.st_mode)
    }

    open func read(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    open func write(_ data: Data, at url: URL, options: Data.WritingOptions) throws {
        try data.write(to: url, options: options)
    }

    open func remove(at url: URL) throws(FileItemError) {
        let code = url.withUnsafeFileSystemRepresentation { path in
            path.map { unlink($0) == 0 ? 0 : errno }
        } ?? EINVAL
        guard code == 0 else {
            throw FileItemError(code: code)
        }
    }

    open func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    open func excludeFromBackup(at url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    open func itemReplacementDirectory(appropriateFor url: URL) throws -> URL {
        try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
    }

    open func move(at url: URL, to destination: URL) throws(FileItemError) {
        let code = url.withUnsafeFileSystemRepresentation { source in
            destination.withUnsafeFileSystemRepresentation { target in
                guard let source, let target else {
                    return EINVAL
                }

                return rename(source, target) == 0 ? 0 : errno
            }
        }
        guard code == 0 else {
            throw FileItemError(code: code)
        }
    }

    open func removeInBackground(at url: URL) {
        DispatchQueue.global(qos: .utility).async { [self] in
            try? fileManager.removeItem(at: url)
        }
    }
}

// MARK: - FileItemError

/// Why a lookup, removal or move failed: the cases the storage tells apart, and the `errno` code of any other.
public enum FileItemError: Error, Equatable, Sendable {
    /// `ENOENT`: nothing is at the path.
    case notFound
    /// `EPERM`: the item is protected while the device is locked, or the sandbox denies access; `remove` also refuses a
    /// folder with it.
    case notPermitted
    case other(Int32)

    init(code: Int32) {
        switch code {
        case ENOENT:    self = .notFound
        case EPERM:     self = .notPermitted
        default:        self = .other(code)
        }
    }
}

// MARK: - FileAttributeType + Mode

extension FileAttributeType {
    /// The type in an `lstat` mode; a FIFO is `.typeUnknown`, as `FileAttributeType` has no case for one.
    init(mode: mode_t) {
        switch mode & S_IFMT {
        case S_IFREG:   self = .typeRegular
        case S_IFDIR:   self = .typeDirectory
        case S_IFLNK:   self = .typeSymbolicLink
        case S_IFSOCK:  self = .typeSocket
        case S_IFCHR:   self = .typeCharacterSpecial
        case S_IFBLK:   self = .typeBlockSpecial
        default:        self = .typeUnknown
        }
    }
}
