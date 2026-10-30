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
public protocol FileLocator {
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
open class DefaultFileLocator: FileLocator {
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

    open func directory(for scope: FileStorage.Scope) throws(FileStorage.Error) -> URL {
        switch scope {
        case let .own(retention, protection, namespace):
            // Before the lookups, so the namespace's error doesn't depend on the system
            let namespaceFolder = try Self.folderName(for: namespace)
            let app = try baseDirectory(for: retention).appendingPathComponent(Self.encoded(bundleIdentifier ?? processName), isDirectory: true)
            return Self.directory(in: app, namespaceFolder: namespaceFolder, protection: protection)
        case let .appGroup(groupId, protection, namespace):
            let namespaceFolder = try Self.folderName(for: namespace)
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
        guard let key = Self.decoded(fileName).map({ FileStorage.Key($0) }), (try? Self.fileName(forKey: key)) == fileName else {
            return nil
        }

        return key
    }

    // MARK: Helpers

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
        base.appendingPathComponent(namespaceFolder, isDirectory: true).appendingPathComponent(folderName(for: protection), isDirectory: true)
    }

    private static func folderName(for namespace: FileStorage.Namespace) throws(FileStorage.Error) -> String {
        let folderName = encoded(namespace.string) + "!"
        guard folderName.utf8.count <= maximumNameLength else {
            throw .invalidNamespace(namespace)
        }

        return folderName
    }

    // One letter: every byte here counts toward the system's 1024-byte limit on a whole path
    private static func folderName(for protection: FileStorage.Protection) -> String {
        switch protection {
        case .inherited:                return "i"
        case .none:                     return "n"
        case .untilFirstUnlock:         return "u"
        case .whileLocked:              return "w"
        case .whileLockedUnlessOpen:    return "o"
        }
    }

    private static func fileName(forKey key: FileStorage.Key) throws(FileStorage.Error) -> String {
        let fileName = encoded(key.string)
        guard fileName.utf8.count <= maximumNameLength else {
            throw .invalidKey(key)
        }

        return fileName
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

    private static func decoded(_ name: String) -> String? {
        guard name != "%" else {
            return ""
        }

        var bytes = [UInt8]()
        var rest = Substring(name).utf8
        while let byte = rest.popFirst() {
            if keptBytes.contains(byte) {
                bytes.append(byte)
            } else if byte == UInt8(ascii: "!"), let letter = rest.popFirst(), lowercaseLetters.contains(letter) {
                bytes.append(letter - lowercaseLetters.lowerBound + capitals.lowerBound)
            } else if byte == UInt8(ascii: "%"),
                      let high = rest.popFirst().flatMap(hexDigits.firstIndex),
                      let low = rest.popFirst().flatMap(hexDigits.firstIndex) {
                bytes.append(UInt8(high << 4 | low))
            } else {
                return nil
            }
        }

        return String(decoding: bytes, as: UTF8.self)
    }
}
