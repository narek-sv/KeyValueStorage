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
    
    public required nonisolated init(domain: Domain?) throws {
        self.fileManager = .default
        self.domain = domain
        
        if let domain {
            guard let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: domain) else {
                throw Error.failedToInitSharedDirectory
            }
            
            root = url
        } else {
            guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw Error.failedToFindDocumentsDirectory
            }
            
            root = url
        }
    }
    
    // MARK: Main Functionality
    
    public func fetch(forKey key: Key) async throws -> Data? {
        fileManager.contents(atPath: directory(for: key).path)
    }
    
    public func save(_ value: Data, forKey key: Key) async throws {
        try execute {
            let directory = directory(for: key)
            let directoryPath = directory.path

            if fileManager.fileExists(atPath: directoryPath) {
                try fileManager.removeItem(at: directory)
            }
            
            if !fileManager.createFile(atPath: directoryPath, contents: value) {
                throw Error.failedToSave
            }
        }
    }
    
    public func delete(forKey key: Key) async throws {
        try execute {
            try fileManager.removeItem(at: directory(for: key))
        }
    }
    
    public func clear() async throws {
        try execute {
            try fileManager.removeItem(at: root)
        }
    }
    
    // MARK: Helpers
    
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
