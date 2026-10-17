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
    /// The bundle identifier, or the process name for command-line tools.
    var appIdentifier: String { get }

    /// `FileManager.temporaryDirectory`.
    var temporaryDirectory: URL { get }

    /// `FileManager.urls(for:in: .userDomainMask).first`.
    func directory(for directory: FileManager.SearchPathDirectory) -> URL?

    /// `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`; `nil` outside the group.
    func groupDirectory(for groupId: String) -> URL?
}

/// Live lookups, adopted only by default backing storages, so mocks never reach the system.
protocol FoundationStorageDirectoryResolving: StorageDirectoryResolving { }

extension FoundationStorageDirectoryResolving {
    var appIdentifier: String {
        AppIdentifier.current
    }

    var temporaryDirectory: URL {
        FileManager.default.temporaryDirectory
    }

    func directory(for directory: FileManager.SearchPathDirectory) -> URL? {
        FileManager.default.urls(for: directory, in: .userDomainMask).first
    }

    func groupDirectory(for groupId: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)
    }
}

/// The identity in app-private paths and suite names, so they stay private even without App Sandbox.
enum AppIdentifier {
    static var current: String {
        Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
    }
}

// MARK: - StorageDirectory

/// A file-based storage's folder: `<base>/<app id>/<container>/<folder>`, or `<group container>/<container>/<folder>`.
enum StorageDirectory {
    case applicationSupport(container: String)
    case cache(container: String)
    case documents(container: String)
    case temporary(container: String)
    case appGroup(groupId: String, container: String)

    enum Failure: Error {
        /// No such base directory.
        case directoryNotFound(String)

        /// No container for the App Group.
        case groupNotFound(String)
    }

    func url(storageFolder: String, resolver: any StorageDirectoryResolving) throws -> URL {
        let folder: URL
        switch self {
        case let .applicationSupport(container):
            folder = try Self.base(.applicationSupportDirectory, named: "Application Support", resolver: resolver)
                .appendingPathComponent(resolver.appIdentifier, isDirectory: true)
                .appendingPathComponent(container, isDirectory: true)
        case let .cache(container):
            folder = try Self.base(.cachesDirectory, named: "Caches", resolver: resolver)
                .appendingPathComponent(resolver.appIdentifier, isDirectory: true)
                .appendingPathComponent(container, isDirectory: true)
        case let .documents(container):
            folder = try Self.base(.documentDirectory, named: "Documents", resolver: resolver)
                .appendingPathComponent(resolver.appIdentifier, isDirectory: true)
                .appendingPathComponent(container, isDirectory: true)
        case let .temporary(container):
            folder = resolver.temporaryDirectory
                .appendingPathComponent(resolver.appIdentifier, isDirectory: true)
                .appendingPathComponent(container, isDirectory: true)
        case let .appGroup(groupId, container):
            guard let url = resolver.groupDirectory(for: groupId) else {
                throw Failure.groupNotFound(groupId)
            }

            folder = url.appendingPathComponent(container, isDirectory: true)
        }

        return folder.appendingPathComponent(storageFolder, isDirectory: true)
    }

    private static func base(
        _ directory: FileManager.SearchPathDirectory,
        named name: String,
        resolver: any StorageDirectoryResolving
    ) throws -> URL {
        guard let url = resolver.directory(for: directory) else {
            throw Failure.directoryNotFound(name)
        }

        return url
    }
}
