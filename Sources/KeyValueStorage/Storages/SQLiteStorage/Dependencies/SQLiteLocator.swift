//
//  SQLiteLocator.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation

// MARK: - SQLiteLocator

/// - Note: `clear()` empties the whole database, so a custom locator gives each scope its own.
public protocol SQLiteLocator {
    /// The storage creates the file's folder.
    func databaseURL(for scope: SQLiteStorage.Scope) throws(SQLiteStorage.Error) -> URL

    func storedKey(forKey key: SQLiteStorage.Key, in scope: SQLiteStorage.Scope) -> String
}

// MARK: - DefaultSQLiteLocator

/// Keeps the hidden `.KeyValueStorage.sqlite` in the scope's folder, named as `DefaultFileLocator` names it, so file and
/// SQLite storages of one scope share the folder.
open class DefaultSQLiteLocator: SQLiteLocator {
    private static let databaseName = ".KeyValueStorage.sqlite"
    private static let maximumNameLength = 255
    private static let keptBytes = Set("abcdefghijklmnopqrstuvwxyz0123456789_-".utf8)
    private static let capitals = UInt8(ascii: "A")...UInt8(ascii: "Z")
    private static let lowercaseLetters = UInt8(ascii: "a")...UInt8(ascii: "z")
    private static let hexDigits = Array("0123456789abcdef".utf8)

    private var fileManager: FileManager { .default }

    public init() { }

    // MARK: System Directories

    /// `FileManager.urls(for:in: .userDomainMask).first`.
    open func systemDirectory(_ directory: FileManager.SearchPathDirectory) -> URL? {
        fileManager.urls(for: directory, in: .userDomainMask).first
    }

    /// `FileManager.temporaryDirectory`.
    open var temporaryDirectory: URL {
        fileManager.temporaryDirectory
    }

    /// `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`; `nil` outside the group.
    open func groupDirectory(for groupId: String) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupId)
    }

    /// `Bundle.main.bundleIdentifier`.
    open var bundleIdentifier: String? {
        Bundle.main.bundleIdentifier
    }

    /// `ProcessInfo.processInfo.processName`, the app's identifier where there's no bundle ID.
    open var processName: String {
        ProcessInfo.processInfo.processName
    }

    // MARK: Names

    open func databaseURL(for scope: SQLiteStorage.Scope) throws(SQLiteStorage.Error) -> URL {
        let folder: URL
        switch scope {
        case let .own(retention, protection, namespace):
            // Before the lookups, so the namespace's error doesn't depend on the system
            let namespaceFolder = try Self.folderName(for: namespace)
            let app = try baseDirectory(for: retention).appendingPathComponent(Self.encoded(bundleIdentifier ?? processName), isDirectory: true)
            folder = Self.directory(in: app, namespaceFolder: namespaceFolder, protection: protection)
        case let .appGroup(groupId, protection, namespace):
            let namespaceFolder = try Self.folderName(for: namespace)
            guard !groupId.isEmpty, let container = groupDirectory(for: groupId) else {
                throw .groupDirectoryNotFound(groupId)
            }

            folder = Self.directory(in: container, namespaceFolder: namespaceFolder, protection: protection)
        }

        return folder.appendingPathComponent(Self.databaseName, isDirectory: false)
    }

    open func storedKey(forKey key: SQLiteStorage.Key, in scope: SQLiteStorage.Scope) -> String {
        key.string
    }

    // MARK: Helpers

    private func baseDirectory(for retention: SQLiteStorage.Retention) throws(SQLiteStorage.Error) -> URL {
        switch retention {
        case .persistent:   return try baseDirectory(.applicationSupportDirectory)
        case .cache:        return try baseDirectory(.cachesDirectory)
        case .temporary:    return temporaryDirectory
        }
    }

    private func baseDirectory(_ directory: FileManager.SearchPathDirectory) throws(SQLiteStorage.Error) -> URL {
        guard let url = systemDirectory(directory) else {
            throw .directoryNotFound(directory)
        }

        return url
    }

    private static func directory(in base: URL, namespaceFolder: String, protection: SQLiteStorage.Protection) -> URL {
        base.appendingPathComponent(namespaceFolder, isDirectory: true).appendingPathComponent(folderName(for: protection), isDirectory: true)
    }

    private static func folderName(for namespace: SQLiteStorage.Namespace) throws(SQLiteStorage.Error) -> String {
        let folderName = encoded(namespace.string) + "!"
        guard folderName.utf8.count <= maximumNameLength else {
            throw .invalidNamespace(namespace)
        }

        return folderName
    }

    // One letter, as in `DefaultFileLocator`: every byte here counts toward the system's 1024-byte limit on a whole path
    private static func folderName(for protection: SQLiteStorage.Protection) -> String {
        switch protection {
        case .inherited:                return "i"
        case .none:                     return "n"
        case .untilFirstUnlock:         return "u"
        case .whileLocked:              return "w"
        case .whileLockedUnlessOpen:    return "o"
        }
    }

    private static func encoded(_ name: String) -> String {
        guard !name.isEmpty else {
            return "%"
        }

        var encoded = [UInt8]()
        for byte in name.utf8 {
            if keptBytes.contains(byte) {
                encoded.append(byte)
            } else if capitals.contains(byte) {
                encoded += [UInt8(ascii: "!"), byte - capitals.lowerBound + lowercaseLetters.lowerBound]
            } else {
                encoded += [UInt8(ascii: "%"), hexDigits[Int(byte >> 4)], hexDigits[Int(byte & 0x0F)]]
            }
        }

        return String(decoding: encoded, as: UTF8.self)
    }
}
