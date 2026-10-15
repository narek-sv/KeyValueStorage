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
    public let domain: Domain?
    
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
        
    struct Domain: KeyValueDataStorageDomain {
        /// The keychain access group the items are saved in.
        public let accessGroup: String
        public let service: String

        /// - Parameters:
        ///   - accessGroup: An access group your app belongs to, as written in its entitlements: an App Group,
        ///     such as `group.com.company.app`, or a Keychain Sharing group, such as `ABCDE12345.com.company.shared`.
        ///   - service: Defaults to `KeyValueStorage.<accessGroup>`. It must differ from `KeychainStorage.defaultService`,
        ///     because queries without an access group search every group, so the default storage would otherwise see and clear shared items.
        public init(accessGroup: String, service: String? = nil) {
            self.accessGroup = accessGroup
            self.service = service ?? KeychainStorage.defaultService + "." + accessGroup
        }
        
        /// A Keychain Sharing group, whose access group is `<teamId>.<groupId>`.
        /// For an App Group, use `init(accessGroup:service:)`, because App Groups have no team prefix.
        public init(groupId: String, teamId: String, service: String? = nil) {
            self.init(accessGroup: teamId + "." + groupId, service: service)
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
