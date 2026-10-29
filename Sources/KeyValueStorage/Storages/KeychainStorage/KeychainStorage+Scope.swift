//
//  KeychainStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - KeychainStorage + Scope

public extension KeychainStorage {
    /// `nil` saves items without a service.
    /// - Warning: With a `nil` namespace, queries match every service, so `clear()` deletes every generic password
    ///   the scope can reach, other code's too.
    enum Namespace: KeyValueDataStorageNamespace {
        case service(named: String)
    }

    enum Scope: KeyValueDataStorageScope {
        /// - Warning: Saves use the app's default access group, but fetches, deletes and `clear()` also reach
        ///   App Group and Keychain Sharing items.
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
