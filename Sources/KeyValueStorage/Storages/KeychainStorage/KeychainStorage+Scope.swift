//
//  KeychainStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - KeychainStorage + Scope

public extension KeychainStorage {
    /// `nil` uses service `""`, which items saved without a service also have.
    /// - Warning: With a `nil` namespace, `clear()` also removes other code's items without a service.
    enum Namespace: KeyValueDataStorageNamespace {
        case service(named: String)
    }

    enum Scope: KeyValueDataStorageScope {
        /// - Warning: Queries search every access group the app has, so they also reach other code's items
        ///   with the scope's service there.
        case app(namespace: Namespace? = nil)
        /// An App Group ID, or a Keychain Sharing group with its team ID prefix.
        case appGroup(groupId: String, namespace: Namespace? = nil)
        
        public var namespace: Namespace? {
            switch self {
            case let .app(namespace):         return namespace
            case let .appGroup(_, namespace): return namespace
            }
        }
        
        public static var `default`: Self {
            .app(namespace: .service(named: Self.defaultName))
        }
    }
}
