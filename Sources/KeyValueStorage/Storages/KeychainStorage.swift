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

    private let keychain: KeychainWrapper
    public nonisolated let domain: Domain?
    
    // MARK: Initializers
    
    public required init() {
        self.domain = nil
        self.keychain = KeychainWrapper(serviceName: Self.defaultService)
    }

    public required init(domain: Domain) {
        self.domain = domain
        self.keychain = KeychainWrapper(serviceName: domain.service, accessGroup: domain.accessGroup)
    }
    
    public init(keychain: KeychainWrapper) {
        self.keychain = keychain
        self.domain = nil
    }
    
    // MARK: Main Functionality
    
    public func fetch(forKey key: Key) throws -> Data? {
        try execute {
            try keychain.get(forKey: key.name, isSynchronizable: key.isSynchronizable)
        }
    }
    
    public func save(_ value: Data, forKey key: Key) throws {
        try execute {
            try keychain.set(value, forKey: key.name, withAccessibility: key.accessibility, isSynchronizable: key.isSynchronizable)
        }
    }
    
    public func delete(forKey key: Key) throws {
        try execute {
            try keychain.remove(forKey: key.name, isSynchronizable: key.isSynchronizable)
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
            try keychain.removeAll()
        }
    }
    
    // MARK: Helpers
    
    private func convert(error: Swift.Error) -> Error {
        if case let .status(status) = error as? KeychainWrapperError {
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
    /// The service of items saved without a domain. It does not depend on the bundle identifier,
    /// so `clear()` doesn't remove items of other keychain libraries that use the bundle identifier as their service.
    /// Items without a domain live in the process's default access group; use a `Domain` to share them with extensions.
    nonisolated static let defaultService = "KeyValueStorage"
    
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
    
    enum Domain: KeyValueDataStorageDomain {
        /// An app-level keychain namespace selected by service.
        /// A non-`nil` service isolates the items created through that domain. A `nil` service deliberately removes the
        /// service filter, so fetch, delete and clear can match unrelated generic-password items in any entitled access group.
        case app(service: String?)
      
        /// A shared keychain namespace in an App Group or a dedicated Keychain Sharing access group.
        /// `groupId` is passed unchanged as `kSecAttrAccessGroup`. A non-`nil` service isolates one logical container
        /// inside that group; a `nil` service can match every generic-password service in the group.
        case appGroup(groupId: String, service: String?)
        
        /// A package-owned service that keeps default operations, especially `clear()`, away from service-less keychain items.
        public static var `default`: Self {
            .app(service: Self.defaultContainerName)
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
