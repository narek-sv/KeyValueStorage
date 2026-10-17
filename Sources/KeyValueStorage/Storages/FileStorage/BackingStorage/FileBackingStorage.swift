//
//  FileBackingStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - FileBackingStorage

public protocol FileBackingStorage: StorageDirectoryResolving {
    func read(at url: URL) throws -> Data
    func write(_ data: Data, at url: URL, options: Data.WritingOptions) throws
    func remove(at url: URL) throws

    func createDirectory(at url: URL) throws
    func contents(at url: URL) throws -> [String]
}

// MARK: - DefaultFileBackingStorage

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
