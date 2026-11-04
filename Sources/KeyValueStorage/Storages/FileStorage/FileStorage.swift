//
//  FileStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.12.23.
//

import Foundation

// MARK: - FileStorage

/// Values in files, one per key; every save replaces the file atomically.
/// - Note: A save survives an app crash, but files aren't flushed to the disk on every save, so a power loss or system
///   crash right after one can lose it. A save the app is killed in leaves a hidden temporary file in the scope's folder,
///   which `clear()` never removes.
/// - Note: Only a regular file at a key's path is a value. Anything else there, or anything but a folder where the scope's
///   folder goes, is never read or removed, and `save` throws `.pathOccupied`. Links are never followed.
/// - Warning: A folder that another process puts at a key's path between `delete`'s check and its removal is removed.
/// - Note: Thread-safe: an instance can be shared between threads and tasks, but a sequence of operations isn't atomic.
public final class FileStorage: DataStorage, Sendable {

    // MARK: Properties

    private let backingStore: any FileBackingStore
    private let locator: any FileLocator
    private let root: URL
    private let writingOptions: Data.WritingOptions
    private let isExcludedFromBackup: Bool

    public let scope: Scope

    // MARK: Initializers

    public init(
        scope: Scope,
        backingStore: any FileBackingStore = DefaultFileBackingStoreWrapper(),
        locator: any FileLocator = DefaultFileLocator()
    ) throws(Error) {
        self.root = try locator.directory(for: scope)
        self.writingOptions = Self.writingOptions(for: scope)
        self.isExcludedFromBackup = Self.isExcludedFromBackup(scope)
        self.scope = scope
        self.backingStore = backingStore
        self.locator = locator
    }

    public convenience init(scope: Scope) throws(Error) {
        try self.init(scope: scope, backingStore: DefaultFileBackingStoreWrapper(), locator: DefaultFileLocator())
    }

    /// The `default` scope's storage.
    public convenience init() throws(Error) {
        try self.init(scope: .default)
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) throws(Error) -> Data? {
        let url = try url(for: key)
        guard try hasValue(at: url) else {
            return nil
        }

        return try Self.execute { () throws -> Data? in
            do {
                return try backingStore.read(at: url)
            } catch CocoaError.fileReadNoSuchFile {
                // Removed by another call since the check: there's no value
                return nil
            }
        }
    }

    public func save(_ value: Data, forKey key: Key) throws(Error) {
        let url = try url(for: key)
        switch try itemType(at: root) {
        case .typeDirectory?:   break
        case nil:               try Self.execute { try backingStore.createDirectory(at: root) }
        default:                throw .pathOccupied(root)
        }

        // Before every write, so a value never lands in the folder without it, even after a failed save
        if isExcludedFromBackup {
            try Self.execute { try backingStore.excludeFromBackup(at: root) }
        }

        switch try itemType(at: url) {
        case .typeRegular?, nil:    break
        default:                    throw .pathOccupied(url)
        }

        try Self.execute { try backingStore.write(value, at: url, options: writingOptions) }
    }

    public func delete(forKey key: Key) throws(Error) {
        try removeValue(at: url(for: key))
    }

    /// Tries to remove every value of the scope, even after one fails.
    /// - Throws: `.clearIncomplete` with each value it couldn't remove; any other error before it removes anything.
    public func clear() throws(Error) {
        guard try itemType(at: root) == .typeDirectory else {
            return
        }

        // The folder can also hold SQLite's files and other code's; it's checked once, above
        let names = try Self.execute { try backingStore.itemNames(at: root) }
        var failures = [Key: Error]()
        for name in names {
            guard let key = valueKey(forFileName: name) else {
                continue
            }

            do throws(Error) {
                let url = root.appendingPathComponent(name, isDirectory: false)
                if try isFile(at: url) {
                    try remove(at: url)
                }
            } catch {
                failures[key] = error
            }
        }

        guard failures.isEmpty else {
            throw .clearIncomplete(failures)
        }
    }

    // MARK: Helpers

    /// The folder comes first, so a file in its place is never looked into.
    private func hasValue(at url: URL) throws(Error) -> Bool {
        guard try itemType(at: root) == .typeDirectory else {
            return false
        }

        return try isFile(at: url)
    }

    /// Never a folder: `remove` deletes a folder with everything inside.
    private func isFile(at url: URL) throws(Error) -> Bool {
        try itemType(at: url) == .typeRegular
    }

    private func removeValue(at url: URL) throws(Error) {
        guard try hasValue(at: url) else {
            return
        }

        try remove(at: url)
    }

    private func remove(at url: URL) throws(Error) {
        try Self.execute {
            do {
                try backingStore.remove(at: url)
            } catch CocoaError.fileNoSuchFile {
                // Removed by another call since the check: the value is gone either way
            }
        }
    }

    /// The key of a name this storage writes, byte for byte, or `nil`: a locator's reverse mapping can accept more.
    private func valueKey(forFileName name: String) -> Key? {
        guard let key = locator.key(forFileName: name, in: scope),
              let encoded = try? locator.fileName(forKey: key, in: scope),
              Key(encoded) == Key(name) else {
            return nil
        }

        return key
    }

    private func url(for key: Key) throws(Error) -> URL {
        try root.appendingPathComponent(locator.fileName(forKey: key, in: scope), isDirectory: false)
    }

    /// `nil` only if nothing is there, so an unreadable path never passes for an empty one.
    private func itemType(at url: URL) throws(Error) -> FileAttributeType? {
        do throws(FileItemError) {
            return try backingStore.itemType(at: url)
        } catch .notFound {
            return nil
        } catch {
            throw Error(error)
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

    private static func isExcludedFromBackup(_ scope: Scope) -> Bool {
        switch scope {
        case .own(.persistentExcludedFromBackup, _, _): return true
        case .own, .appGroup:                           return false
        }
    }

    private static func execute<T>(_ body: () throws -> T) throws(Error) -> T {
        do {
            return try body()
        } catch {
            throw Error(error)
        }
    }
}
