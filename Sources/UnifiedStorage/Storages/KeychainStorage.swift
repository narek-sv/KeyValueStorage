//
//  KeychainStorage.swift
//  
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - Data Storage

@KeychainActor
open class KeychainStorage: KeyValueDataStorage, @unchecked Sendable {
    
    // MARK: Properties

    private let keychain: KeychainHelper
    public let domain: Domain?
    
    // MARK: Initializers

    public required nonisolated init(domain: Domain?) throws {
        self.domain = domain
        
        if let domain {
            keychain = KeychainHelper(serviceName: Self.defaultGroup, accessGroup: domain.accessGroup)
        } else {
            keychain = KeychainHelper(serviceName: Self.defaultGroup)
        }
    }
    
    // MARK: Main Functionality
    
    public func fetch(forKey key: Key) async throws -> Data? {
        try execute {
            try keychain.get(forKey: key.name, withAccessibility: key.accessibility, isSynchronizable: key.isSynchronizable)
        }
    }
    
    public func save(_ value: Data, forKey key: Key) async throws {
        try execute {
            try keychain.set(value, forKey: key.name, withAccessibility: key.accessibility, isSynchronizable: key.isSynchronizable)
        }
    }
    
    public func delete(forKey key: Key) async throws {
        try execute {
            try keychain.remove(forKey: key.name, withAccessibility: key.accessibility, isSynchronizable: key.isSynchronizable)
        }
    }
    
    public func clear() async throws {
        try execute {
            try keychain.removeAll()
        }
    }
    
    // MARK: Helpers
    
    private func convert(error: Swift.Error) -> Error {
        if case let .status(status) = error as? KeychainHelperError {
            return .os(status)
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

public extension KeychainStorage {
    struct Key: KeyValueDataStorageKey {
        public let name: String
        public let accessibility: KeychainAccessibility?
        public let isSynchronizable: Bool
        
        public init(name: String, accessibility: KeychainAccessibility? = nil, isSynchronizable: Bool = false) {
            self.name = name
            self.accessibility = accessibility
            self.isSynchronizable = isSynchronizable
        }
    }
        
    struct Domain: KeyValueDataStorageDomain {
        public let groupId: String
        public let teamId: String
        
        public var accessGroup: String {
            teamId + "." + groupId
        }
    }
    
    enum Error: KeyValueDataStorageError {
        case os(OSStatus)
        case other(Swift.Error)
    }
}

// MARK: - Global Actors

@globalActor
public final class KeychainActor {
    public actor Actor { }
    public static let shared = Actor()
}
