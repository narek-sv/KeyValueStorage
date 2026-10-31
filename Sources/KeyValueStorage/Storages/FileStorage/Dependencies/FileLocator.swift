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
/// - never return a name starting with `.`: SQLite and the system keep dot files in the same folders;
/// - never give two keys names the volume sees as one, such as names that differ only in case;
/// - make `key(forFileName:in:)` the exact inverse of `fileName(forKey:in:)`, or `clear()` leaves files behind.
public protocol FileLocator: Sendable {
    func directory(for scope: FileStorage.Scope) throws(FileStorage.Error) -> URL

    func fileName(forKey key: FileStorage.Key, in scope: FileStorage.Scope) throws(FileStorage.Error) -> String

    /// `nil` for names no key produces.
    func key(forFileName fileName: String, in scope: FileStorage.Scope) -> FileStorage.Key?
}

// MARK: - DefaultFileLocator

/// Encodes keys, namespaces and the app's identifier losslessly into ASCII names: `a`–`z`, `0`–`9`, `_` and `-` stay,
/// a capital is `!` and its lowercase letter, any other byte is `%xx`, and the empty name is `%`. Only names over 255 bytes throw.
/// A scope's folder is `<namespace>!/<protection>`, in `<base>/<app identifier>` for `.own` and in the group's container for `.appGroup`.
/// - Note: Names are exact bytes, not normalized: `"é"` and `"e\u{301}"` are two keys.
/// - Note: A subclass that changes names overrides both name methods.
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

    open func directory(for scope: FileStorage.Scope) throws(FileStorage.Error) -> URL {
        switch scope {
        case let .own(retention, protection, namespace):
            // Before the lookups, so the namespace's error doesn't depend on the system
            let namespaceFolder = try Self.namespaceFolderName(for: namespace)
            let app = try baseDirectory(for: retention).appendingPathComponent(appFolderName, isDirectory: true)
            return Self.directory(in: app, namespaceFolder: namespaceFolder, protection: protection)
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

    open func key(forFileName fileName: String, in scope: FileStorage.Scope) -> FileStorage.Key? {
        // Decoding alone also accepts names the encoding never writes, such as `%41` for `A`
        guard let key = String(portableName: fileName).map({ FileStorage.Key($0) }), (try? Self.fileName(forKey: key)) == fileName else {
            return nil
        }

        return key
    }

    // MARK: Helpers

    private var appFolderName: String {
        ownIdentifier.portableName
    }

    private func baseDirectory(for retention: FileStorage.Retention) throws(FileStorage.Error) -> URL {
        switch retention {
        case .persistent:   return try baseDirectory(.applicationSupportDirectory)
        case .cache:        return try baseDirectory(.cachesDirectory)
        case .temporary:    return temporaryDirectory
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
        case .inherited:                return "i"
        case .none:                     return "n"
        case .untilFirstUnlock:         return "u"
        case .whileLocked:              return "w"
        case .whileLockedUnlessOpen:    return "o"
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
