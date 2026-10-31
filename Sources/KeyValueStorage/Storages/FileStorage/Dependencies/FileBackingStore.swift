//
//  FileBackingStore.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - FileBackingStore

/// One system call per member, without rules: the storage owns them.
public protocol FileBackingStore: Sendable {
    /// `FileManager.attributesOfItem(atPath:)`, which describes a link itself.
    func itemType(at url: URL) throws -> FileAttributeType?
    /// `Data(contentsOf:)`.
    func read(at url: URL) throws -> Data
    /// `Data.write(to:options:)`.
    func write(_ data: Data, at url: URL, options: Data.WritingOptions) throws
    /// `FileManager.removeItem(at:)`.
    /// - Warning: Removes a folder with everything inside.
    func remove(at url: URL) throws
    /// `FileManager.createDirectory(at:withIntermediateDirectories: true)`.
    func createDirectory(at url: URL) throws
    /// `FileManager.contentsOfDirectory(atPath:)`.
    func itemNames(at url: URL) throws -> [String]
}

// MARK: - DefaultFileBackingStoreWrapper

/// The live file system.
/// - Warning: Subclasses inherit `Sendable`: their own state must be thread-safe too.
open class DefaultFileBackingStoreWrapper: FileBackingStore, @unchecked Sendable {
    private var fileManager: FileManager { .default }

    public init() { }

    open func itemType(at url: URL) throws -> FileAttributeType? {
      try fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
    }

    open func read(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    open func write(_ data: Data, at url: URL, options: Data.WritingOptions) throws {
        try data.write(to: url, options: options)
    }

    open func remove(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    open func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    open func itemNames(at url: URL) throws -> [String] {
        try fileManager.contentsOfDirectory(atPath: url.path)
    }
}
