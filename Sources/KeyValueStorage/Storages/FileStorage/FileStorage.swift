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
///   which only `clear()` removes.
/// - Note: Only a regular file at a key's path is a value, and links are never followed. `save` throws `.pathOccupied`
///   instead of replacing anything else there, or anything but a folder where the scope's folder goes.
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
        // The folder first, so a file or a link in its place is never looked into
        guard try itemType(at: root) == .typeDirectory, try itemType(at: url) == .typeRegular else {
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
        do throws(Error) {
            try write(value, at: url)
        } catch {
            // A `clear()` moved the folder out mid-save: the value goes into a new one, as if saved after the clear
            guard try itemType(at: root) == nil else {
                throw error
            }

            try write(value, at: url)
        }
    }

    /// Removes the key's file, or a link in its place but never what it points to; a folder there isn't a value, and stays.
    public func delete(forKey key: Key) throws(Error) {
        let url = try url(for: key)
        // The folder first, so a link in its place is never followed
        guard try itemType(at: root) == .typeDirectory else {
            return
        }

        do throws(FileItemError) {
            try backingStore.remove(at: url)
        } catch .notFound {
            // No value, or removed by another call since the check
        } catch .notPermitted {
            // `remove` refuses a folder, which isn't a value; anything else wasn't permitted
            guard try itemType(at: url) == .typeDirectory else {
                throw Error(.notPermitted)
            }
        } catch {
            throw Error(error)
        }
    }

    /// Empties the scope at once, for every process: one rename moves its folder into a new temporary folder on its
    /// volume, which is deleted in the background; if that fails, the system purges it with its other temporary files.
    /// - Warning: Removes everything in the scope's folder, values or not, so a custom locator gives each scope a folder
    ///   nothing else uses.
    /// - Throws: Only before the move, so the scope is cleared whole or not at all.
    public func clear() throws(Error) {
        guard try itemType(at: root) != nil else {
            return
        }

        let temporaryFolder = try Self.execute { try backingStore.itemReplacementDirectory(appropriateFor: root) }
        // The temporary folder goes whether the move works or not
        defer { backingStore.removeInBackground(at: temporaryFolder) }
        do throws(FileItemError) {
            try backingStore.move(at: root, to: temporaryFolder.appendingPathComponent(root.lastPathComponent, isDirectory: true))
        } catch .notFound {
            // Moved by another call since the check: the scope is empty either way
        } catch {
            throw Error(error)
        }
    }

    // MARK: Helpers

    private func write(_ value: Data, at url: URL) throws(Error) {
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
