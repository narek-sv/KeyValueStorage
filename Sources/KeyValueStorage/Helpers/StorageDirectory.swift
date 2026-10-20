//
//  StorageDirectory.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - StorageDirectoryResolving

/// Directory lookups of file-based storages, provided by their backing storages.
public protocol StorageDirectoryResolving {
    /// `FileManager.temporaryDirectory`.
    var temporaryDirectory: URL { get }

    /// `FileManager.urls(for:in: .userDomainMask).first`.
    func directory(for directory: FileManager.SearchPathDirectory) -> URL?

    /// `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`; `nil` outside the group.
    func groupDirectory(for groupId: String) -> URL?
}

// MARK: - StorageDirectory

/// A file-based storage's folder: the base directory, given directory or group container itself, or its `namespace` subdirectory.
enum StorageDirectory {
    case applicationSupport
    case cache
    case documents
    case temporary
    case directory(at: URL)
    case appGroup(groupId: String)

    enum Failure: Error {
        /// No such base directory.
        case directoryNotFound(String)

        /// No container for the App Group.
        case groupNotFound(String)

        /// Not a file URL.
        case invalidDirectory(URL)
    }

    func url(namespace: String?, resolver: any StorageDirectoryResolving) throws(Failure) -> URL {
        let folder: URL
        switch self {
        case .applicationSupport:
            folder = try Self.base(.applicationSupportDirectory, named: "Application Support", resolver: resolver)
        case .cache:
            folder = try Self.base(.cachesDirectory, named: "Caches", resolver: resolver)
        case .documents:
            folder = try Self.base(.documentDirectory, named: "Documents", resolver: resolver)
        case .temporary:
            folder = resolver.temporaryDirectory
        case let .directory(url):
            guard url.isFileURL else {
                throw Failure.invalidDirectory(url)
            }

            folder = url
        case let .appGroup(groupId):
            guard let url = resolver.groupDirectory(for: groupId) else {
                throw Failure.groupNotFound(groupId)
            }

            folder = url
        }

        return namespace.map { folder.appendingPathComponent($0, isDirectory: true) } ?? folder
    }

    private static func base(
        _ directory: FileManager.SearchPathDirectory,
        named name: String,
        resolver: any StorageDirectoryResolving
    ) throws(Failure) -> URL {
        guard let url = resolver.directory(for: directory) else {
            throw Failure.directoryNotFound(name)
        }

        return url
    }
}
