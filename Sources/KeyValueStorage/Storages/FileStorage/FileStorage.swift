//
//  FileStorage.swift
//
//
//  Created by Narek Sahakyan on 17.12.23.
//

import Foundation

// MARK: - FileStorage

public final class FileStorage: KeyValueDataStorage {
    // Separate from SQLiteStorage's folder
    static let directoryPrefixName = "Files"

    public static var defaultBackingStorage: any FileBackingStorage {
        DefaultFileBackingStorage()
    }

    // MARK: Properties

    private let storage: any FileBackingStorage
    private let root: URL

    public let domain: Domain

    // MARK: Initializers

    /// Resolves the domain's folder, which is created on the first save.
    public init(domain: Domain, backingStorage: any FileBackingStorage) throws {
        self.root = try Self.root(for: domain, resolver: backingStorage)
        self.domain = domain
        self.storage = backingStorage
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) throws -> Data? {
        try execute {
            do {
                return try storage.read(at: url(for: key))
            } catch CocoaError.fileReadNoSuchFile {
                return nil
            }
        }
    }

    public func save(_ value: Data, forKey key: Key) throws {
        try execute {
            let url = try url(for: key)
            let options = Self.writingOptions(for: key.protection)

            do {
                try storage.write(value, at: url, options: options)
            } catch CocoaError.fileNoSuchFile {
                // Missing folder: create it and retry
                try storage.createDirectory(at: root)
                try storage.write(value, at: url, options: options)
            }
        }
    }

    public func delete(forKey key: Key) throws {
        try execute {
            try deleteFileIfExists(at: url(for: key))
        }
    }
    
    public func clear() throws {
        try execute {
            let fileNames: [String]
            do {
                fileNames = try storage.contents(at: root)
            } catch CocoaError.fileReadNoSuchFile {
                // Nothing saved yet
                return
            }

            for fileName in fileNames {
                try deleteFileIfExists(at: root.appendingPathComponent(fileName))
            }
        }
    }
    
    // MARK: Helpers

    private static func root(for domain: Domain, resolver: any StorageDirectoryResolving) throws -> URL {
        let directory: StorageDirectory
        switch domain {
        case let .app(.applicationSupport(container)):  directory = .applicationSupport(container: container)
        case let .app(.cache(container)):               directory = .cache(container: container)
        case let .app(.documents(container)):           directory = .documents(container: container)
        case let .app(.temporary(container)):           directory = .temporary(container: container)
        case let .appGroup(groupId, container):         directory = .appGroup(groupId: groupId, container: container)
        }

        do {
            return try directory.url(storageFolder: directoryPrefixName, resolver: resolver)
        } catch StorageDirectory.Failure.directoryNotFound(let name) {
            throw Error.failedToFindDirectory(name)
        } catch StorageDirectory.Failure.groupNotFound(let groupId) {
            throw Error.failedToFindGroupDirectory(groupId)
        }
    }

    private func deleteFileIfExists(at url: URL) throws {
        do {
            try storage.remove(at: url)
        } catch CocoaError.fileNoSuchFile {
            // ok
        } catch {
            throw error
        }
    }
    
    /// Atomic writes with the key's protection.
    private static func writingOptions(for protection: Key.Protection) -> Data.WritingOptions {
        guard #available(macOS 11, *) else {
            return .atomic // Protection classes need macOS 11
        }

        switch protection {
        case .inherited:                            return .atomic
        case .none:                                 return [.atomic, .noFileProtection]
        case .complete:                             return [.atomic, .completeFileProtection]
        case .completeUnlessOpen:                   return [.atomic, .completeFileProtectionUnlessOpen]
        case .completeUntilFirstUserAuthentication: return [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        }
    }

    /// The key's file, whose name must be one path component that can't escape `root`.
    private func url(for key: Key) throws -> URL {
        let name = key.name
        let fileName = Self.fileName(for: name)
        let isValid = !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\0")
            && fileName.utf8.count <= 255

        guard isValid else {
            throw Error.invalidKey(name)
        }

        return root.appendingPathComponent(fileName, isDirectory: false)
    }

    /// The normalized name with `%` and case-changing characters percent-encoded, so it's unique on case-insensitive volumes.
    private static func fileName(for name: String) -> String {
        var fileName = ""
        for character in name.precomposedStringWithCanonicalMapping {
            let string = String(character)
            if character == "%" || string.folding(options: .caseInsensitive, locale: nil) != string {
                fileName += string.utf8.map { String(format: "%%%02X", $0) }.joined()
            } else {
                fileName += string
            }
        }
        
        return fileName
    }
    
    private func convert(error: Swift.Error) -> Error {
        if let error = error as? FileStorage.Error {
            return error
        }

        if Self.isProtectedDataUnavailable(error) {
            return .protectedDataUnavailable
        }

        return .other(error)
    }

    /// A protected file on a locked device: a permission error caused by `EPERM`, unlike real permissions (`EACCES`).
    static func isProtectedDataUnavailable(_ error: Swift.Error) -> Bool {
        let error = error as NSError
        guard error.domain == NSCocoaErrorDomain,
              error.code == NSFileReadNoPermissionError || error.code == NSFileWriteNoPermissionError,
              let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else {
            return false
        }

        return underlying.domain == NSPOSIXErrorDomain && underlying.code == Int(EPERM)
    }
    
    @discardableResult
    private func execute<T>(_ block: () throws -> T) rethrows -> T {
        do {
            return try block()
        } catch {
            throw convert(error: error)
        }
    }
}
