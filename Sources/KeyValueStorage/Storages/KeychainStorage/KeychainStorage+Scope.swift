//
//  KeychainStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - KeychainStorage + Scope

public extension KeychainStorage {
    /// Separates sets of items by service; `nil` (the default) saves items without a service and matches items of any service.
    /// - Warning: With a `nil` namespace, `clear()` deletes every generic password the scope can reach, including other code's.
    enum Namespace: KeyValueDataStorageNamespace {
        /// The items whose service (`kSecAttrService`) is this name.
        case service(named: String)
    }

    /// The access group of the items, if any, which decides who can read them.
    enum Scope: KeyValueDataStorageScope {
        /// No access group: saves use the app's default access group, and queries search all of the app's access groups.
        /// - Warning: Fetches, deletes and `clear()` also reach the items of App Groups and Keychain Sharing groups.
        case app(namespace: Namespace? = nil)
        /// A shared access group: an App Group ID, or a Keychain Sharing group with its team ID prefix.
        case appGroup(groupId: String, namespace: Namespace? = nil)
        
        public var namespace: Namespace? {
            switch self {
            case let .app(namespace):         return namespace
            case let .appGroup(_, namespace): return namespace
            }
        }
        
        public static var `default`: Self {
            .app(namespace: .service(named: Self.defaultNamespace))
        }
    }
}
