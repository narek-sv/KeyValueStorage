//
//  FileBackingStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - FileBackingStorage

/// File system calls of `FileStorage`; Foundation errors are thrown unchanged.
public protocol FileBackingStorage: StorageDirectoryResolving {
    /// `Data(contentsOf:)`.
    func read(at url: URL) throws -> Data

    /// `Data.write(to:options:)`.
    func write(_ data: Data, at url: URL, options: Data.WritingOptions) throws

    /// `FileManager.removeItem(atPath:)`.
    func remove(at url: URL) throws

    /// `FileManager.createDirectory(atPath:withIntermediateDirectories: true)`.
    func createDirectory(at url: URL) throws

    /// `FileManager.contentsOfDirectory(atPath:)`.
    func contents(at url: URL) throws -> [String]
}

// MARK: - DefaultFileBackingStorage

/// The live `FileBackingStorage`.
final class DefaultFileBackingStorage: FileBackingStorage, FoundationStorageDirectoryResolving {
    private var fileManager: FileManager { .default }

    func read(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, at url: URL, options: Data.WritingOptions) throws {
        try data.write(to: url, options: options)
    }

    func remove(at url: URL) throws {
        try fileManager.removeItem(atPath: url.path)
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(atPath: url.path, withIntermediateDirectories: true)
    }

    func contents(at url: URL) throws -> [String] {
        try fileManager.contentsOfDirectory(atPath: url.path)
    }
}
