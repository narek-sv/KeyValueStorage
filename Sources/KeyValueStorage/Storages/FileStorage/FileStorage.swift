//
//  FileStorage.swift
//
//
//  Created by Narek Sahakyan on 17.12.23.
//

import Foundation

// MARK: - FileStorage

public final class FileStorage: KeyValueDataStorage {

    // MARK: Properties

    private let storage: any FileBackingStore
    private let root: URL

    public let scope: Scope

    // MARK: Initializers

    public init(scope: Scope, backingStorage: any FileBackingStore) throws {
        self.root = try Self.root(for: scope, resolver: backingStorage)
        self.scope = scope
        self.storage = backingStorage
    }

    public convenience init(scope: Scope) throws {
        try self.init(scope: scope, backingStorage: DefaultFileBackingStoreWrapper())
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
                return
            }

            for fileName in fileNames {
                try deleteFileIfExists(at: root.appendingPathComponent(fileName))
            }
        }
    }
    
    // MARK: Helpers

    private static func root(for scope: Scope, resolver: any StorageDirectoryResolving) throws -> URL {
        let directory: StorageDirectory
        switch scope {
        case .app(.applicationSupport, _):  directory = .applicationSupport
        case .app(.cache, _):               directory = .cache
        case .app(.documents, _):           directory = .documents
        case .app(.temporary, _):           directory = .temporary
        case let .app(.directory(url), _):  directory = .directory(at: url)
        case let .appGroup(groupId, _):     directory = .appGroup(groupId: groupId)
        }

        let namespace: String?
        switch scope.namespace {
        case let .directory(name)?: namespace = name
        case nil:                   namespace = nil
        }

        do {
            return try directory.url(namespace: namespace, resolver: resolver)
        } catch StorageDirectory.Failure.directoryNotFound(let name) {
            throw Error.failedToFindDirectory(name)
        } catch StorageDirectory.Failure.groupNotFound(let groupId) {
            throw Error.failedToFindGroupDirectory(groupId)
        } catch StorageDirectory.Failure.invalidDirectory(let url) {
            throw Error.invalidDirectory(url)
        }
    }

    private func deleteFileIfExists(at url: URL) throws {
        do {
            try storage.remove(at: url)
        } catch CocoaError.fileNoSuchFile {
        } catch {
            throw error
        }
    }
    
    private static func writingOptions(for protection: Key.Protection) -> Data.WritingOptions {
        guard #available(macOS 11, *) else {
            return .atomic
        }

        switch protection {
        case .inherited:                            return .atomic
        case .none:                                 return [.atomic, .noFileProtection]
        case .complete:                             return [.atomic, .completeFileProtection]
        case .completeUnlessOpen:                   return [.atomic, .completeFileProtectionUnlessOpen]
        case .completeUntilFirstUserAuthentication: return [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        }
    }

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

    private static func isProtectedDataUnavailable(_ error: Swift.Error) -> Bool {
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
