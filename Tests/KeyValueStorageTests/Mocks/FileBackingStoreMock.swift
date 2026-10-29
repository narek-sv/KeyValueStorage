//
//  FileBackingStoreMock.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 28.10.26.
//

import Foundation
@testable import KeyValueStorage

/// An in-memory file system with Foundation's rules: `remove` deletes a folder with everything inside, `write` needs
/// the folder, missing items throw, and links aren't followed. Records every call, and throws the error set for a call.
final class FileBackingStoreMock: FileBackingStore {
    enum Call: Equatable {
        case itemType(URL)
        case read(URL)
        case write(Data, URL, Data.WritingOptions)
        case remove(URL)
        case createDirectory(URL)
        case itemNames(URL)
    }

    enum Item: Equatable {
        case file(Data)
        case directory
        case link
    }

    var items = [String: Item]()
    var errors = [(call: Call, error: any Error)]()
    private(set) var calls = [Call]()

    func itemType(at url: URL) throws -> FileAttributeType? {
        try record(.itemType(url))
        switch items[url.path] {
        case .file?:        return .typeRegular
        case .directory?:   return .typeDirectory
        case .link?:        return .typeSymbolicLink
        case nil:           throw CocoaError(.fileReadNoSuchFile)
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
        try record(.write(data, url, options))
        guard items[url.deletingLastPathComponent().path] == .directory else {
            throw CocoaError(.fileNoSuchFile)
        }

        guard items[url.path] != .directory else {
            throw CocoaError(.fileWriteUnknown)
        }

        items[url.path] = .file(data)
    }

    func remove(at url: URL) throws {
        try record(.remove(url))
        guard items[url.path] != nil else {
            throw CocoaError(.fileNoSuchFile)
        }

        items = items.filter { $0.key != url.path && !$0.key.hasPrefix(url.path + "/") }
    }

    func createDirectory(at url: URL) throws {
        try record(.createDirectory(url))
        guard items[url.path] ?? .directory == .directory else {
            throw CocoaError(.fileWriteFileExists)
        }

        items[url.path] = .directory
    }

    func itemNames(at url: URL) throws -> [String] {
        try record(.itemNames(url))
        guard items[url.path] == .directory else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        return items.keys
            .map { URL(fileURLWithPath: $0) }
            .filter { $0.deletingLastPathComponent().path == url.path }
            .map(\.lastPathComponent)
            .sorted()
    }

    private func record(_ call: Call) throws {
        calls.append(call)
        if let error = errors.first(where: { $0.call == call })?.error {
            throw error
        }
    }
}
