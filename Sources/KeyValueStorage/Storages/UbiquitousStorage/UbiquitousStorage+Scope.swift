//
//  UbiquitousStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

// MARK: - UbiquitousStorage + Scope

@available(watchOS 9.0, *)
public extension UbiquitousStorage {
    /// Which apps see the values.
    enum Owner: Hashable, Sendable {
        /// The running app or extension.
        /// - Warning: Apps whose entitlements name the same key-value store can read, change and delete its values.
        case own
    }

    enum Scope: DataStorageScope {
        /// Synced to the user's other devices through iCloud.
        /// - Note: Values stay on this device while the user is signed out of iCloud.
        /// - Note: The store holds at most 1 MB of values and 1024 keys in all.
        /// - Warning: Without the iCloud key-value store entitlement, the store keeps nothing, and nothing reports it.
        case iCloud(Owner, namespace: Namespace)

        public static var `default`: Self {
            .iCloud(.own, namespace: defaultNamespace)
        }

        /// `iCloud(_:namespace:)`, with any string as the namespace, such as one made at runtime.
        public static func iCloud(_ owner: Owner, namespace: String) -> Self {
            .iCloud(owner, namespace: Namespace(namespace))
        }
    }
}
