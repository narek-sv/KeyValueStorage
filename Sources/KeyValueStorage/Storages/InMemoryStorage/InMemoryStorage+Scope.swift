//
//  InMemoryStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - InMemoryStorage + Scope

public extension InMemoryStorage {
    /// Separates sets of values within the process; `nil` (the default) uses one unnamed bucket.
    enum Namespace: KeyValueDataStorageNamespace {
        /// The values in the bucket with this name.
        case bucket(named: String)
    }
    
    /// The memory of the current process, which keeps the values until it exits.
    enum Scope: KeyValueDataStorageScope {
        /// In the process's memory, shared by every storage with the same namespace.
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
