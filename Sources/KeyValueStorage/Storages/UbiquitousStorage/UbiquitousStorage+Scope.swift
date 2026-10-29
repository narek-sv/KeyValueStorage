//
//  UbiquitousStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

// MARK: - UbiquitousStorage + Scope

@available(watchOS 9.0, *)
public extension UbiquitousStorage {
    /// `nil` stores the keys as they are, with `%` and `/` percent-encoded.
    /// - Warning: With a `nil` namespace, `clear()` removes every `Data` value a key could have written, other code's too,
    ///   on all of the user's devices; never values of other types or namespaces' keys.
    enum Namespace: KeyValueDataStorageNamespace {
        /// Stored as `<name>/<key>`, with `%` and `/` in `name` percent-encoded.
        case keyPrefix(named: String)
    }
    
    enum Scope: KeyValueDataStorageScope {
        /// The store of the app's iCloud entitlement, synced across the user's devices.
        case shared(namespace: Namespace? = nil)
        
        public var namespace: Namespace? {
            switch self {
            case .shared(let namespace):  return namespace
            }
        }
        
        public static var `default`: Self {
            .shared(namespace: .keyPrefix(named: Self.defaultName))
        }
    }
}
