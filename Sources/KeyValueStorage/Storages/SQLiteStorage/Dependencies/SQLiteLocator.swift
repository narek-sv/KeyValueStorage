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

    func storedKey(forKey key: String, in scope: SQLiteStorage.Scope) -> String
}

// MARK: - DefaultSQLiteLocator

/// Keeps the hidden `.KeyValueStorage.sqlite` in the scope's directory or its namespace's folder, named with
/// `DefaultFileLocator`'s encoding.
open class DefaultSQLiteLocator: SQLiteLocator {
    private static let databaseName = ".\(SQLiteStorage.Scope.defaultName).sqlite"
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

    // MARK: Names

    open func databaseURL(for scope: SQLiteStorage.Scope) throws(SQLiteStorage.Error) -> URL {
        // Before the lookups, so the namespace's error doesn't depend on the system
        let folderName = try scope.namespace.map(Self.folderName(for:))

        let base: URL
        switch scope {
        case .app(.applicationSupport, _, _):
            base = try baseDirectory(.applicationSupportDirectory)
        case .app(.cache, _, _):
            base = try baseDirectory(.cachesDirectory)
        case .app(.documents, _, _):
            base = try baseDirectory(.documentDirectory)
        case .app(.temporary, _, _):
            base = temporaryDirectory
        case let .app(.directory(url), _, _):
            guard url.isFileURL else {
                throw .invalidDirectory(url)
            }

            base = url
        case let .appGroup(groupId, _, _):
            guard let url = groupDirectory(for: groupId) else {
                throw .groupDirectoryNotFound(groupId)
            }

            base = url
        }

        let folder = folderName.map { base.appendingPathComponent($0, isDirectory: true) } ?? base
        return folder.appendingPathComponent(Self.databaseName, isDirectory: false)
    }

    open func storedKey(forKey key: String, in scope: SQLiteStorage.Scope) -> String {
        key
    }

    // MARK: Helpers

    private func baseDirectory(_ directory: FileManager.SearchPathDirectory) throws(SQLiteStorage.Error) -> URL {
        guard let url = systemDirectory(directory) else {
            throw .directoryNotFound(directory)
        }

        return url
    }

    private static func folderName(for namespace: SQLiteStorage.Namespace) throws(SQLiteStorage.Error) -> String {
        switch namespace {
        case let .directory(name):
            let folderName = encoded(name) + "!"
            guard folderName.utf8.count <= maximumNameLength else {
                throw .invalidNamespace(name)
            }

            return folderName
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
