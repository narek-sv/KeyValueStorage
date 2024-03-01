//
//  UserDefaultsStorage.swift
//  
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - Data Storage

@UserDefaultsActor
open class UserDefaultsStorage: KeyValueDataStorage, @unchecked Sendable {
    
    // MARK: Properties

    private let userDefaults: UserDefaults
    public let domain: Domain?
    
    // MARK: Initializers
    
    public required init() {
        self.domain = nil
        self.userDefaults = .standard
    }

    public required init(domain: Domain) throws {
        guard let defaults = UserDefaults(suiteName: domain) else {
            throw Error.failedToInitSharedDefaults
        }
        
        self.domain = domain
        self.userDefaults = defaults
    }
    
    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        self.domain = nil
    }
    
    // MARK: Main Functionality

    public func fetch(forKey key: Key) -> Data? {
        userDefaults.data(forKey: key)
    }
    
    public func save(_ value: Data, forKey key: Key) {
        userDefaults.set(value, forKey: key)
    }
    
    public func delete(forKey key: Key) {
        userDefaults.removeObject(forKey: key)
    }
    
    public func set(_ value: Data?, forKey key: Key) {
        if let value = value {
            save(value, forKey: key)
        } else {
            delete(forKey: key)
        }
    }
    
    public func clear() {
        userDefaults.removePersistentDomain(forName: domain ?? Self.defaultGroup)
    }
}

// MARK: - Associated Types

public extension UserDefaultsStorage {
    typealias Key = String
    typealias Domain = String
    
    enum Error: KeyValueDataStorageError {
        case failedToInitSharedDefaults
    }
}

// MARK: - Global Actors

@globalActor
public final class UserDefaultsActor {
    public actor Actor { }
    public static let shared = Actor()
}
