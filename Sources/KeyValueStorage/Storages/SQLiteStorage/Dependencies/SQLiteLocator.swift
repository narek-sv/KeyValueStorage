//
//  SQLiteLocator.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation

// MARK: - SQLiteLocator

/// - Note: `clear()` empties the whole database, so a custom locator gives each scope its own.
public protocol SQLiteLocator: Sendable {
    /// The storage creates the file's folder.
    func databaseURL(for scope: SQLiteStorage.Scope) throws(SQLiteStorage.Error) -> URL

    func storedKey(forKey key: SQLiteStorage.Key, in scope: SQLiteStorage.Scope) -> String
}

// MARK: - DefaultSQLiteLocator

/// Keeps the hidden `.KeyValueStorage.sqlite` in the scope's folder, named as `DefaultFileLocator` names it, so file and
/// SQLite storages of one scope share the folder.
/// - Warning: Subclasses inherit `Sendable`: their own state must be thread-safe too.
open class DefaultSQLiteLocator: SQLiteLocator, @unchecked Sendable {
    private static let databaseName = ".KeyValueStorage.sqlite"
    private static let maximumNameLength = 255
    /// Ends namespace folders, as in `DefaultFileLocator`.
    private static let namespaceMark = "!"

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

    // MARK: App Identifier

    /// `OwnIdentity.identifier`.
    open var ownIdentifier: String {
        OwnIdentity.identifier
    }

    // MARK: Names

    open func databaseURL(for scope: SQLiteStorage.Scope) throws(SQLiteStorage.Error) -> URL {
        let folder: URL
        switch scope {
        case let .own(retention, protection, namespace):
            // Before the lookups, so the namespace's error doesn't depend on the system
            let namespaceFolder = try Self.namespaceFolderName(for: namespace)
            let app = try baseDirectory(for: retention).appendingPathComponent(appFolderName, isDirectory: true)
            folder = Self.directory(in: app, namespaceFolder: namespaceFolder, protection: protection)
        case let .appGroup(groupId, protection, namespace):
            let namespaceFolder = try Self.namespaceFolderName(for: namespace)
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

    private var appFolderName: String {
        ownIdentifier.portableName
    }

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
        base.appendingPathComponent(namespaceFolder, isDirectory: true).appendingPathComponent(protectionFolderName(for: protection), isDirectory: true)
    }

    private static func namespaceFolderName(for namespace: SQLiteStorage.Namespace) throws(SQLiteStorage.Error) -> String {
        let folderName = namespace.string.portableName + namespaceMark
        guard folderName.utf8.count <= maximumNameLength else {
            throw .invalidNamespace(namespace)
        }

        return folderName
    }

    // One letter, as in `DefaultFileLocator`: every byte here counts toward the system's 1024-byte limit on a whole path
    private static func protectionFolderName(for protection: SQLiteStorage.Protection) -> String {
        switch protection {
        case .inherited:                return "i"
        case .none:                     return "n"
        case .untilFirstUnlock:         return "u"
        case .whileLocked:              return "w"
        case .whileLockedUnlessOpen:    return "o"
        }
    }
}
