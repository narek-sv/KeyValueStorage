//
//  FileStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.12.23.
//

import Foundation

// MARK: - FileStorage

/// Values in files, one per key; every save replaces the file atomically.
/// - Note: Only a regular file at a key's path is a value. Anything else there, or anything but a folder where the scope's
///   folder goes, is never read or removed, and `save` throws `.pathOccupied`. Links are never followed.
/// - Warning: A folder that another process puts at a key's path between `delete`'s check and its removal is removed.
public final class FileStorage: KeyValueDataStorage {

    // MARK: Properties

    private let backingStore: any FileBackingStore
    private let locator: any FileLocator
    private let root: URL
    private let writingOptions: Data.WritingOptions

    public let scope: Scope

    // MARK: Initializers

    public init(scope: Scope, backingStore: any FileBackingStore, locator: any FileLocator) throws(Error) {
        self.root = try locator.directory(for: scope)
        self.writingOptions = Self.writingOptions(for: scope)
        self.scope = scope
        self.backingStore = backingStore
        self.locator = locator
    }

    public convenience init(scope: Scope) throws(Error) {
        try self.init(scope: scope, backingStore: DefaultFileBackingStoreWrapper(), locator: DefaultFileLocator())
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) throws(Error) -> Data? {
        let url = try url(for: key)
        guard try hasValue(at: url) else {
            return nil
        }

        return try execute { try backingStore.read(at: url) }
    }

    public func save(_ value: Data, forKey key: Key) throws(Error) {
        let url = try url(for: key)
        switch try itemType(at: root) {
        case .typeDirectory?:   break
        case nil:               try execute { try backingStore.createDirectory(at: root) }
        default:                throw .pathOccupied(root)
        }

        switch try itemType(at: url) {
        case .typeRegular?, nil:    break
        default:                    throw .pathOccupied(url)
        }

        try execute { try backingStore.write(value, at: url, options: writingOptions) }
    }

    public func delete(forKey key: Key) throws(Error) {
        try removeValue(at: url(for: key))
    }

    public func clear() throws(Error) {
        guard try itemType(at: root) == .typeDirectory else {
            return
        }

        // The folder can also hold SQLite's files and other code's
        let names = try execute { try backingStore.itemNames(at: root) }
        for name in names where isValueName(name) {
            try removeValue(at: root.appendingPathComponent(name, isDirectory: false))
        }
    }

    // MARK: Helpers

    /// The folder comes first, so a file in its place is never looked into.
    private func hasValue(at url: URL) throws(Error) -> Bool {
        guard try itemType(at: root) == .typeDirectory else {
            return false
        }

        return try itemType(at: url) == .typeRegular
    }

    /// Never a folder: `remove` deletes a folder with everything inside.
    private func removeValue(at url: URL) throws(Error) {
        guard try hasValue(at: url) else {
            return
        }

        try execute { try backingStore.remove(at: url) }
    }

    private func isValueName(_ name: String) -> Bool {
        guard let key = locator.key(forFileName: name, in: scope) else {
            return false
        }

        return (try? locator.fileName(forKey: key, in: scope)) == name
    }

    private func url(for key: Key) throws(Error) -> URL {
        try root.appendingPathComponent(locator.fileName(forKey: key, in: scope), isDirectory: false)
    }

    /// `nil` only if nothing is there, so an unreadable path never passes for an empty one.
    private func itemType(at url: URL) throws(Error) -> FileAttributeType? {
        try execute {
            do {
                return try backingStore.itemType(at: url)
            } catch CocoaError.fileReadNoSuchFile {
                return nil
            }
        }
    }

    private static func writingOptions(for scope: Scope) -> Data.WritingOptions {
        guard #available(macOS 11, *) else {
            return .atomic
        }

        switch scope {
        case let .own(_, protection, _), let .appGroup(_, protection, _):
            return (protection.fileProtection ?? []).union(.atomic)
        }
    }

    private func execute<T>(_ body: () throws -> T) throws(Error) -> T {
        do {
            return try body()
        } catch {
            throw Error(error)
        }
    }
}
