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
    private let userDefaults: UserDefaults
    public let domain: Domain?
    
    public required nonisolated init(domain: Domain?) throws {
        self.domain = domain
        
        if let domain {
            guard let defaults = UserDefaults(suiteName: domain) else {
                throw Error.failedToInitSharedDefaults
            }
            
            userDefaults = defaults
        } else {
            userDefaults = .standard
        }
    }
    
    public func fetch(forKey key: Key) throws -> Data? {
        userDefaults.data(forKey: key)
    }
    
    public func save(_ value: Data, forKey key: Key) throws {
        userDefaults.set(value, forKey: key)
    }
    
    public func delete(forKey key: Key) throws {
        userDefaults.removeObject(forKey: key)
    }
    
    public func clear() throws {
        userDefaults.removePersistentDomain(forName: domain ?? Self.defaultGroup)
    }
    
}

// MARK: - Associated Types

public extension UserDefaultsStorage {
    typealias Key = String
    typealias Domain = String
    
    enum Error: KeyValueDataStorageError {
        case failedToInitSharedDefaults
        case other(Swift.Error)
    }
}

// MARK: - Global Actors

@globalActor
public final class UserDefaultsActor {
    public actor Actor { }
    public static let shared = Actor()
}
