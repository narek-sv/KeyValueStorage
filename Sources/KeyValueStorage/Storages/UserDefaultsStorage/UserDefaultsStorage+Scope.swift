//
//  UserDefaultsStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - UserDefaultsStorage + Scope

public extension UserDefaultsStorage {
    /// `nil` stores the keys as they are, with `%` and `/` percent-encoded.
    /// - Warning: With a `nil` namespace, `clear()` removes every `Data` value a key could have written, other code's too;
    ///   never values of other types or namespaces' keys.
    enum Namespace: KeyValueDataStorageNamespace {
        /// Stored as `<name>/<key>`, with `%` and `/` in `name` percent-encoded.
        case keyPrefix(named: String)
    }
    
    enum AppScope: Hashable, Sendable {
        case standard
        /// - Warning: On macOS without App Sandbox, every app of the user that uses this name shares the suite.
        case suite(named: String)
    }
    
    enum Scope: KeyValueDataStorageScope {
        case app(AppScope, namespace: Namespace? = nil)
        /// Shared by every app and extension in the group.
        case appGroup(groupId: String, namespace: Namespace? = nil)
        
        public var namespace: Namespace? {
            switch self {
            case let .app(_, namespace):        return namespace
            case let .appGroup(_, namespace):   return namespace
            }
        }
        
        public static var `default`: Self {
            .app(.suite(named: Self.defaultName), namespace: .keyPrefix(named: Self.defaultName))
        }
    }
}
