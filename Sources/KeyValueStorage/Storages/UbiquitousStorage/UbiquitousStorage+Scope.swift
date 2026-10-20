//
//  UbiquitousStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

// MARK: - UbiquitousStorage + Scope

@available(watchOS 9.0, *)
public extension UbiquitousStorage {
    /// Separates sets of values within the store; `nil` (the default) stores the keys as is.
    /// - Warning: With a `nil` namespace, `clear()` removes every key of the store, on all of the user's devices.
    enum Namespace: KeyValueDataStorageNamespace {
        /// Keys stored as `<name>/<key>`, with `%` and `/` in `name` percent-encoded.
        case keyPrefix(named: String)
    }
    
    /// The iCloud key-value store of the values.
    enum Scope: KeyValueDataStorageScope {
        /// The store of the app's iCloud entitlement, synced across the user's devices.
        case shared(namespace: Namespace? = nil)
        
        public var namespace: Namespace? {
            switch self {
            case .shared(let namespace):  return namespace
            }
        }
        
        public static var `default`: Self {
            .shared(namespace: .keyPrefix(named: Self.defaultNamespace))
        }
    }
}
