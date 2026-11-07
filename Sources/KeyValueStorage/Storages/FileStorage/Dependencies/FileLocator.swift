//
//  FileLocator.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 28.10.26.
//

import Foundation

// MARK: - FileLocator

/// Names a file storage's folder and files.
///
/// A custom locator must:
/// - give each scope a folder nothing else uses;
/// - never return a name starting with `.`: the system keeps dot files in the same folders;
/// - never give two keys names the volume sees as one, such as names that differ only in case.
public protocol FileLocator: Sendable {
    /// - Warning: `clear()` removes this folder with everything inside, so it's the scope's alone.
    func directory(for scope: FileStorage.Scope) throws(FileStorage.Error) -> URL

    func fileName(forKey key: FileStorage.Key, in scope: FileStorage.Scope) throws(FileStorage.Error) -> String
}

// MARK: - DefaultFileLocator

/// Encodes keys, namespaces and the app's identifier losslessly into ASCII names: `a`–`z`, `0`–`9`, `_` and `-` stay,
/// a capital is `!` and its lowercase letter, any other byte is `%xx`, and the empty name is `%`. Only names over 255 bytes throw.
/// A scope's folder is `<namespace>!/<protection>`: in `<base>/<app identifier>` for `.own`, in its subfolder `x` for
/// `.persistentExcludedFromBackup`, and in the group's container for `.appGroup`.
/// - Note: Names are exact bytes, not normalized: `"é"` and `"e\u{301}"` are two keys.
/// - Warning: Subclasses inherit `Sendable`: their own state must be thread-safe too.
open class DefaultFileLocator: FileLocator, @unchecked Sendable {
    private static let maximumNameLength = 255
    /// Ends namespace folders: a portable name never does, so they never clash with items named like keys.
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

    open func directory(for scope: FileStorage.Scope) throws(FileStorage.Error) -> URL {
        switch scope {
        case let .own(retention, protection, namespace):
            // Before the lookups, so the namespace's error doesn't depend on the system
            let namespaceFolder = try Self.namespaceFolderName(for: namespace)
            return try Self.directory(in: appDirectory(for: retention), namespaceFolder: namespaceFolder, protection: protection)
        case let .appGroup(groupId, protection, namespace):
            let namespaceFolder = try Self.namespaceFolderName(for: namespace)
            guard !groupId.isEmpty, let container = groupDirectory(for: groupId) else {
                throw .groupDirectoryNotFound(groupId)
            }

            return Self.directory(in: container, namespaceFolder: namespaceFolder, protection: protection)
        }
    }

    open func fileName(forKey key: FileStorage.Key, in scope: FileStorage.Scope) throws(FileStorage.Error) -> String {
        try Self.fileName(forKey: key)
    }

    // MARK: Helpers

    private var appFolderName: String {
        ownIdentifier.portableName
    }

    // `.persistentExcludedFromBackup` shares `.persistent`'s base, so its folders are in `x`: one letter, as protections
    // are, and never a namespace folder, which ends with `!`
    private func appDirectory(for retention: FileStorage.Retention) throws(FileStorage.Error) -> URL {
        let app = try baseDirectory(for: retention).appendingPathComponent(appFolderName, isDirectory: true)
        switch retention {
        case .persistentExcludedFromBackup:     return app.appendingPathComponent("x", isDirectory: true)
        case .persistent, .cache, .temporary:   return app
        }
    }

    private func baseDirectory(for retention: FileStorage.Retention) throws(FileStorage.Error) -> URL {
        switch retention {
        case .persistent, .persistentExcludedFromBackup:    return try baseDirectory(.applicationSupportDirectory)
        case .cache:                                        return try baseDirectory(.cachesDirectory)
        case .temporary:                                    return temporaryDirectory
        }
    }

    private func baseDirectory(_ directory: FileManager.SearchPathDirectory) throws(FileStorage.Error) -> URL {
        guard let url = systemDirectory(directory) else {
            throw .directoryNotFound(directory)
        }

        return url
    }

    private static func directory(in base: URL, namespaceFolder: String, protection: FileStorage.Protection) -> URL {
        base.appendingPathComponent(namespaceFolder, isDirectory: true).appendingPathComponent(protectionFolderName(for: protection), isDirectory: true)
    }

    private static func namespaceFolderName(for namespace: FileStorage.Namespace) throws(FileStorage.Error) -> String {
        let folderName = namespace.string.portableName + namespaceMark
        guard folderName.utf8.count <= maximumNameLength else {
            throw .invalidNamespace(namespace)
        }

        return folderName
    }

    // One letter: every byte here counts toward the system's 1024-byte limit on a whole path
    private static func protectionFolderName(for protection: FileStorage.Protection) -> String {
        switch protection {
        case .inherited:             return "i"
        case .none:                  return "n"
        case .afterFirstUnlock:      return "u"
        case .whenUnlocked:          return "w"
        case .whenUnlockedOrOpen:    return "o"
        }
    }

    private static func fileName(forKey key: FileStorage.Key) throws(FileStorage.Error) -> String {
        let fileName = key.string.portableName
        guard fileName.utf8.count <= maximumNameLength else {
            throw .invalidKey(key)
        }

        return fileName
    }
}
