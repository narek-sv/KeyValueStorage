//
//  InMemoryStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - InMemoryStorage + Scope

public extension InMemoryStorage {
    /// `nil` uses one unnamed bucket.
    enum Namespace: KeyValueDataStorageNamespace {
        case bucket(named: String)
    }
    
    /// Values live until the process exits.
    enum Scope: KeyValueDataStorageScope {
        /// Shared by every storage with the same namespace.
        case app(namespace: Namespace? = nil)
        
        public var namespace: Namespace? {
            switch self {
            case let .app(namespace):   return namespace
            }
        }
        
        public static var `default`: Self {
            .app(namespace: .bucket(named: Self.defaultName))
        }
    }
}
