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
    
    public required init() throws {
        let fileManager = FileManager.default
        guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw Error.failedToFindDocumentsDirectory
        }
        
        self.root = url.appendingPathComponent(Self.defaultGroup, isDirectory: true)
        self.domain = nil
        self.fileManager = fileManager
    }
    
    public required init(domain: Domain) throws {
        let fileManager = FileManager.default
        guard let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: domain) else {
            throw Error.failedToInitSharedDirectory
        }
        
        self.root = url.appendingPathComponent(Self.defaultGroup, isDirectory: true)
        self.domain = domain
        self.fileManager = fileManager
    }
    
    // MARK: Main Functionality
    
    public func fetch(forKey key: Key) throws -> Data? {
        fileManager.contents(atPath: directory(for: key).path)
    }
    
    public func save(_ value: Data, forKey key: Key) throws {
        try execute {
            let directory = directory(for: key)
            let directoryPath = directory.path
            
            try createDirectoryIfDoesntExist(path: root.path)
            try deleteFileIfExists(path: directoryPath)
            
            if !fileManager.createFile(atPath: directoryPath, contents: value) {
                throw Error.failedToSave
            }
        }
    }
    
    public func delete(forKey key: Key) throws {
        try execute {
            try deleteFileIfExists(path: directory(for: key).path)
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
            if let fileNames = try? fileManager.contentsOfDirectory(atPath: root.path) {
                for fileName in fileNames {
                    let path = root.appendingPathComponent(fileName).path
                    try deleteFileIfExists(path: path)
                }
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
    
    private func createDirectoryIfDoesntExist(path: String) throws {
        do {
            try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch CocoaError.fileWriteFileExists {
            // ok
        } catch {
            throw error
        }
    }
    
    private func directory(for key: Key) -> URL {
        root.appendingPathComponent(key)
    }
    
    private func convert(error: Swift.Error) -> Error {
        .other(error)
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
    typealias Key = String
    typealias Domain = String
    
    enum Error: KeyValueDataStorageError {
        case failedToSave
        case failedToInitSharedDirectory
        case failedToFindDocumentsDirectory
        case other(Swift.Error)
    }
}

// MARK: - Global Actors

@globalActor
public final class FileActor {
    public actor Actor { }
    public static let shared = Actor()
}
