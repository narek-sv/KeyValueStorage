//
//  FileStorage.swift
//
//
//  Created by Narek Sahakyan on 17.12.23.
//

import Foundation

// MARK: - Data Storage

@FileActor
open class FileStorage: KeyValueDataStorage, @unchecked Sendable {
    
    // MARK: Properties
    
    private let fileManager: FileManager
    private let root: URL
    public let domain: Domain?
    
    // MARK: Initializers
    
    /// Stores files in `Application Support/<bundle identifier>/KeyValueStorage`.
    /// Application Support isn't visible to the user, the bundle identifier keeps non-sandboxed macOS apps apart,
    /// and the dedicated folder keeps `clear()` away from the app's own files.
    public required init() throws {
        let fileManager = FileManager.default
        guard let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw Error.failedToFindApplicationSupportDirectory
        }
        
        self.root = url
            .appendingPathComponent(Self.defaultGroup, isDirectory: true)
            .appendingPathComponent(Self.directoryName, isDirectory: true)
        self.domain = nil
        self.fileManager = fileManager
    }
    
    /// Stores files in `<app group container>/KeyValueStorage`.
    /// The path doesn't depend on the bundle identifier, so the app and its extensions share the same files.
    public required init(domain: Domain) throws {
        let fileManager = FileManager.default
        guard let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: domain) else {
            throw Error.failedToInitSharedDirectory
        }
        
        self.root = url.appendingPathComponent(Self.directoryName, isDirectory: true)
        self.domain = domain
        self.fileManager = fileManager
    }
    
    public init(fileManager: FileManager, root: URL) {
        self.fileManager = fileManager
        self.root = root
        self.domain = nil
    }
    
    // MARK: Main Functionality
    
    public func fetch(forKey key: Key) throws -> Data? {
        try execute {
            do {
                return try Data(contentsOf: url(for: key))
            } catch CocoaError.fileReadNoSuchFile {
                return nil
            }
        }
    }
    
    public func save(_ value: Data, forKey key: Key) throws {
        try execute {
            let url = try url(for: key)
            
            do {
                try value.write(to: url, options: .atomic)
            } catch CocoaError.fileNoSuchFile {
                // The storage directory doesn't exist yet, so create it only when it's actually missing
                try fileManager.createDirectory(atPath: root.path, withIntermediateDirectories: true)
                try value.write(to: url, options: .atomic)
            }
        }
    }
    
    public func delete(forKey key: Key) throws {
        try execute {
            try deleteFileIfExists(path: url(for: key).path)
        }
    }
    
    public func set(_ value: Data?, forKey key: Key) throws {
        if let value = value {
            try save(value, forKey: key)
        } else {
            try delete(forKey: key)
        }
    }
    
    public func clear() throws {
        try execute {
            let fileNames: [String]
            do {
                fileNames = try fileManager.contentsOfDirectory(atPath: root.path)
            } catch CocoaError.fileReadNoSuchFile {
                // Nothing has been saved yet
                return
            }
            
            for fileName in fileNames {
                let path = root.appendingPathComponent(fileName).path
                try deleteFileIfExists(path: path)
            }
        }
    }
    
    // MARK: Helpers
    
    private func deleteFileIfExists(path: String) throws {
        do {
            try fileManager.removeItem(atPath: path)
        } catch CocoaError.fileNoSuchFile {
            // ok
        } catch {
            throw error
        }
    }
    
    /// The key is used as the file name, so it must be a single path component that can't escape `root`.
    private func url(for key: Key) throws -> URL {
        let isValid = !key.isEmpty
            && key != "."
            && key != ".."
            && !key.contains("/")
            && !key.contains("\0")
            && key.utf8.count <= 255
        
        guard isValid else {
            throw Error.invalidKey(key)
        }
        
        return root.appendingPathComponent(key, isDirectory: false)
    }
    
    private func convert(error: Swift.Error) -> Error {
        if let error = error as? FileStorage.Error {
            return error
        }
        
        return .other(error)
    }
    
    @discardableResult
    private func execute<T>(_ block: () throws -> T) rethrows -> T {
        do {
            return try block()
        } catch {
            throw convert(error: error)
        }
    }
}

// MARK: - Associated Types

public extension FileStorage {
    /// The name of the folder that holds the stored files.
    nonisolated static let directoryName = "KeyValueStorage"
    
    typealias Key = String
    typealias Domain = String
    
    enum Error: KeyValueDataStorageError {
        case failedToInitSharedDirectory
        case failedToFindApplicationSupportDirectory
        case invalidKey(String)
        case other(Swift.Error)
    }
}

// MARK: - Global Actors

@globalActor
public final class FileActor {
    public actor Actor { }
    public static let shared = Actor()
}
