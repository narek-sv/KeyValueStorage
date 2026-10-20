//
//  FileBackingStore.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - FileBackingStore

public protocol FileBackingStore: StorageDirectoryResolving {
    func read(at url: URL) throws -> Data
    func write(_ data: Data, at url: URL, options: Data.WritingOptions) throws
    func remove(at url: URL) throws

    func createDirectory(at url: URL) throws
    /// The names of the regular files in the directory, without its folders.
    func fileNames(at url: URL) throws -> [String]
}

// MARK: - DefaultFileBackingStoreWrapper

/// The live file system; subclass it to change single operations, such as where a directory resolves.
open class DefaultFileBackingStoreWrapper: FileBackingStore {
    private var fileManager: FileManager { .default }

    public init() { }

    open var temporaryDirectory: URL {
        fileManager.temporaryDirectory
    }

    open func directory(for directory: FileManager.SearchPathDirectory) -> URL? {
        fileManager.urls(for: directory, in: .userDomainMask).first
    }

    open func groupDirectory(for groupId: String) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupId)
    }

    open func read(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    open func write(_ data: Data, at url: URL, options: Data.WritingOptions) throws {
        try data.write(to: url, options: options)
    }

    open func remove(at url: URL) throws {
        try fileManager.removeItem(atPath: url.path)
    }

    open func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(atPath: url.path, withIntermediateDirectories: true)
    }

    open func fileNames(at url: URL) throws -> [String] {
        try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true }
            .map(\.lastPathComponent)
    }
}
