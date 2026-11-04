//
//  SQLiteLocator.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation

// MARK: - SQLiteLocator

/// - Note: `clear()` empties the whole database, so a custom locator gives each scope its own.
/// - Warning: Keep databases out of file storages' folders, which their `clear()` may empty.
public protocol SQLiteLocator: Sendable {
    /// The storage creates the file's folder.
    func databaseURL(for scope: SQLiteStorage.Scope) throws(SQLiteStorage.Error) -> URL

    func storedKey(forKey key: SQLiteStorage.Key, in scope: SQLiteStorage.Scope) -> String
}

// MARK: - DefaultSQLiteLocator

/// Keeps a scope's database, `<protection>.sqlite`, in the folder `<namespace>+`, next to the `<namespace>!` where
/// `DefaultFileLocator` keeps the scope's files: names are encoded as there, and databases never share a folder with files.
/// - Warning: Subclasses inherit `Sendable`: their own state must be thread-safe too.
open class DefaultSQLiteLocator: SQLiteLocator, @unchecked Sendable {
    private static let maximumNameLength = 255
    /// Ends namespace folders: a portable name never has a `+`, and `DefaultFileLocator`'s end with `!`.
    private static let namespaceMark = "+"

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

    /// `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`: `nil` for an empty id, and on a device for a group
    /// the app isn't in; macOS and the Simulator give any other id a container.
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
        switch scope {
        case let .own(retention, protection, namespace):
            // Before the lookups, so the namespace's error doesn't depend on the system
            let namespaceFolder = try Self.namespaceFolderName(for: namespace)
            return try Self.databaseURL(in: appDirectory(for: retention), namespaceFolder: namespaceFolder, protection: protection)
        case let .appGroup(groupId, protection, namespace):
            let namespaceFolder = try Self.namespaceFolderName(for: namespace)
            guard !groupId.isEmpty, let container = groupDirectory(for: groupId) else {
                throw .groupDirectoryNotFound(groupId)
            }

            return Self.databaseURL(in: container, namespaceFolder: namespaceFolder, protection: protection)
        }
    }

    open func storedKey(forKey key: SQLiteStorage.Key, in scope: SQLiteStorage.Scope) -> String {
        key.string
    }

    // MARK: Helpers

    private var appFolderName: String {
        ownIdentifier.portableName
    }

    // As in `DefaultFileLocator`: `.persistentExcludedFromBackup` shares `.persistent`'s base, so its folders are in `x`,
    // never a namespace folder, which ends with `+`
    private func appDirectory(for retention: SQLiteStorage.Retention) throws(SQLiteStorage.Error) -> URL {
        let app = try baseDirectory(for: retention).appendingPathComponent(appFolderName, isDirectory: true)
        switch retention {
        case .persistentExcludedFromBackup:     return app.appendingPathComponent("x", isDirectory: true)
        case .persistent, .cache, .temporary:   return app
        }
    }

    private func baseDirectory(for retention: SQLiteStorage.Retention) throws(SQLiteStorage.Error) -> URL {
        switch retention {
        case .persistent, .persistentExcludedFromBackup:    return try baseDirectory(.applicationSupportDirectory)
        case .cache:                                        return try baseDirectory(.cachesDirectory)
        case .temporary:                                    return temporaryDirectory
        }
    }

    private func baseDirectory(_ directory: FileManager.SearchPathDirectory) throws(SQLiteStorage.Error) -> URL {
        guard let url = systemDirectory(directory) else {
            throw .directoryNotFound(directory)
        }

        return url
    }

    private static func databaseURL(in base: URL, namespaceFolder: String, protection: SQLiteStorage.Protection) -> URL {
        base.appendingPathComponent(namespaceFolder, isDirectory: true).appendingPathComponent(databaseName(for: protection), isDirectory: false)
    }

    private static func namespaceFolderName(for namespace: SQLiteStorage.Namespace) throws(SQLiteStorage.Error) -> String {
        let folderName = namespace.string.portableName + namespaceMark
        guard folderName.utf8.count <= maximumNameLength else {
            throw .invalidNamespace(namespace)
        }

        return folderName
    }

    // Named with the letter of the protection's folder in `DefaultFileLocator`
    private static func databaseName(for protection: SQLiteStorage.Protection) -> String {
        switch protection {
        case .inherited:             return "i.sqlite"
        case .none:                  return "n.sqlite"
        case .afterFirstUnlock:      return "u.sqlite"
        case .whenUnlocked:          return "w.sqlite"
        case .whenUnlockedOrOpen:    return "o.sqlite"
        }
    }
}
