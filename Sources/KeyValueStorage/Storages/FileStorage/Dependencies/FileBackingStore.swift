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
    /// `FileManager.removeItem(at:)`.
    /// - Warning: Removes a folder with everything inside.
    func remove(at url: URL) throws
    /// `FileManager.createDirectory(at:withIntermediateDirectories: true)`.
    func createDirectory(at url: URL) throws
    /// `URL.setResourceValues(_:)` with `isExcludedFromBackup`, which on a folder covers everything inside.
    func excludeFromBackup(at url: URL) throws
    /// `FileManager.contentsOfDirectory(atPath:)`.
    func itemNames(at url: URL) throws -> [String]
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

    open func remove(at url: URL) throws {
        try fileManager.removeItem(at: url)
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

    open func itemNames(at url: URL) throws -> [String] {
        try fileManager.contentsOfDirectory(atPath: url.path)
    }
}

// MARK: - FileItemError

/// Why `itemType(at:)` failed: the cases the storage tells apart, and the `errno` code of any other.
public enum FileItemError: Error, Equatable, Sendable {
    /// `ENOENT`: nothing is at the path.
    case notFound
    /// `EPERM`: the item is protected while the device is locked, or the sandbox denies access.
    case notPermitted
    case other(Int32)

    init(code: Int32) {
        switch code {
        case ENOENT:    self = .notFound
        case EPERM:     self = .notPermitted
        default:        self = .other(code)
        }
    }

    var code: Int32 {
        switch self {
        case .notFound:         return ENOENT
        case .notPermitted:     return EPERM
        case let .other(code):  return code
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
