//
//  FileBackingStoreMock.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 28.10.26.
//

import Foundation
@testable import KeyValueStorage

/// An in-memory file system with the system's rules: `remove` deletes a file or a link but refuses a folder, `move`
/// takes an item with everything inside, `write` needs the folder, missing items throw, and links aren't followed.
/// Records every call, and throws the error set for a call; `removeInBackground` deletes at once.
/// Unchecked: used from one test at a time.
final class FileBackingStoreMock: FileBackingStore, @unchecked Sendable {
    enum Call: Equatable {
        case itemType(URL)
        case read(URL)
        case write(Data, URL, Data.WritingOptions)
        case remove(URL)
        case createDirectory(URL)
        case excludeFromBackup(URL)
        case itemReplacementDirectory(URL)
        case move(URL, URL)
        case removeInBackground(URL)
    }

    enum Item: Equatable {
        case file(Data)
        case directory
        case link
    }

    /// The folder `itemReplacementDirectory(appropriateFor:)` creates.
    static let temporaryFolder = URL(fileURLWithPath: "/temporary-items/1", isDirectory: true)

    var items = [String: Item]()
    var errors = [(call: Call, error: any Error)]()
    /// Runs before each write, such as to clear the folder the way another call would.
    var beforeWrite: ((FileBackingStoreMock) -> Void)?
    private(set) var calls = [Call]()

    /// Throws only a `FileItemError` given in `errors`, as the real one throws nothing else.
    func itemType(at url: URL) throws(FileItemError) -> FileAttributeType {
        try recordItemCall(.itemType(url))
        switch items[url.path] {
        case .file?:        return .typeRegular
        case .directory?:   return .typeDirectory
        case .link?:        return .typeSymbolicLink
        case nil:           throw .notFound
        }
    }

    func read(at url: URL) throws -> Data {
        try record(.read(url))
        switch items[url.path] {
        case let .file(data)?:  return data
        case .directory?, .link?:   throw CocoaError(.fileReadUnknown)
        case nil:                   throw CocoaError(.fileReadNoSuchFile)
        }
    }

    func write(_ data: Data, at url: URL, options: Data.WritingOptions) throws {
        beforeWrite?(self)
        try record(.write(data, url, options))
        guard items[url.deletingLastPathComponent().path] == .directory else {
            throw CocoaError(.fileNoSuchFile)
        }

        guard items[url.path] != .directory else {
            throw CocoaError(.fileWriteUnknown)
        }

        items[url.path] = .file(data)
    }

    /// Throws only a `FileItemError`, as `unlink` does.
    func remove(at url: URL) throws(FileItemError) {
        try recordItemCall(.remove(url))
        switch items[url.path] {
        case .directory?:
            throw .notPermitted
        case .file?, .link?:
            items[url.path] = nil
        case nil:
            throw .notFound
        }
    }

    func createDirectory(at url: URL) throws {
        try record(.createDirectory(url))
        guard items[url.path] ?? .directory == .directory else {
            throw CocoaError(.fileWriteFileExists)
        }

        items[url.path] = .directory
    }

    func excludeFromBackup(at url: URL) throws {
        try record(.excludeFromBackup(url))
    }

    func itemReplacementDirectory(appropriateFor url: URL) throws -> URL {
        try record(.itemReplacementDirectory(url))
        items[Self.temporaryFolder.path] = .directory
        return Self.temporaryFolder
    }

    /// Throws only a `FileItemError`, as `rename` does.
    func move(at url: URL, to destination: URL) throws(FileItemError) {
        try recordItemCall(.move(url, destination))
        guard items[url.path] != nil else {
            throw .notFound
        }

        guard items[destination.deletingLastPathComponent().path] == .directory else {
            throw .notFound
        }

        for (path, item) in items where path == url.path || path.hasPrefix(url.path + "/") {
            items[path] = nil
            items[destination.path + path.dropFirst(url.path.count)] = item
        }
    }

    func removeInBackground(at url: URL) {
        calls.append(.removeInBackground(url))
        items = items.filter { $0.key != url.path && !$0.key.hasPrefix(url.path + "/") }
    }

    private func record(_ call: Call) throws {
        calls.append(call)
        if let error = errors.first(where: { $0.call == call })?.error {
            throw error
        }
    }

    private func recordItemCall(_ call: Call) throws(FileItemError) {
        calls.append(call)
        if let error = errors.first(where: { $0.call == call })?.error as? FileItemError {
            throw error
        }
    }
}
