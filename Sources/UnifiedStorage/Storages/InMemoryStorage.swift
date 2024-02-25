//
//  InMemoryStorage.swift
//
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - Data Storage

@InMemoryActor
open class InMemoryStorage: KeyValueDataStorage, @unchecked Sendable {

    // MARK: Properties

    internal static var container = [Domain?: [Key: Data]]() // not thread safe, for internal use only
    public let domain: Domain?
    
    // MARK: Initializers
    
    public required init() {
        self.domain = nil
    }
    
    public required init(domain: Domain) {
        self.domain = domain
    }
    
    // MARK: Main Functionality
    
    public func fetch(forKey key: Key) -> Data? {
        Self.container[domain]?[key]
    }
    
    public func save(_ value: Data, forKey key: Key) {
        if Self.container[domain] == nil {
            Self.container[domain] = [:]
        }
        
        Self.container[domain]?[key] = value
    }
    
    public func set(_ value: Data?, forKey key: Key) {
        if let value = value {
            save(value, forKey: key)
        } else {
            delete(forKey: key)
        }
    }
    
    public func delete(forKey key: Key) {
        Self.container[domain]?[key] = nil
    }
    
    public func clear() {
        Self.container[domain] = [:]
    }
}

// MARK: - Associated Types

public extension InMemoryStorage {
    typealias Key = String
    typealias Domain = String
    
    enum Error: KeyValueDataStorageError {
        case other(Swift.Error)
    }
}

// MARK: - Global Actors

@globalActor
public final class InMemoryActor {
    public actor Actor { }
    public static let shared = Actor()
}
