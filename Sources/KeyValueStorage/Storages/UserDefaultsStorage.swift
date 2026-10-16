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
    public nonisolated let domain: Domain?
    
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
    
    /// Removes every value of this storage's `UserDefaults` domain, including values that weren't saved through this storage.
    ///
    /// The keys are removed one by one instead of with `removePersistentDomain(forName:)`, because an injected
    /// `UserDefaults` doesn't expose its suite name. Removing a key affects only the instance's own domain,
    /// so values of other domains in the search list, such as the global or registration domain, are kept.
    public func clear() {
        for key in userDefaults.dictionaryRepresentation().keys {
            userDefaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Associated Types

public extension UserDefaultsStorage {
    typealias Key = String
    
    enum AppDomain: KeyValueDataStorageAppDomain {
        /// The app's standard defaults domain.
        /// Clearing this domain removes defaults that weren't saved through `KeyValueStorage`, so callers must opt in explicitly.
        case standard
      
        /// A named defaults suite that is private to the current app.
        /// The storage qualifies this logical name with the app identity so it can't be mistaken for an App Group suite.
        case suite(named: String)
    }
    
    enum Domain: KeyValueDataStorageDomain {
        /// A defaults domain that belongs only to the current app.
        case app(AppDomain)
      
        /// The shared defaults suite of an App Group to which the current target is entitled.
        case appGroup(groupId: String)
        
        /// A package-owned app suite, rather than the app's standard defaults domain, so clearing the default storage is isolated.
        public static var `default`: Self {
            .app(.suite(named: Self.defaultContainerName))
        }
    }
    
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
