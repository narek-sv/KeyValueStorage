//
//  UserDefaultsStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - UserDefaultsStorage + Scope

public extension UserDefaultsStorage {
    /// Separates sets of values within a suite; `nil` (the default) stores the keys as is.
    /// - Warning: With a `nil` namespace, `clear()` removes every key of the suite, including other code's.
    enum Namespace: KeyValueDataStorageNamespace {
        /// Keys stored as `<name>/<key>`, with `%` and `/` in `name` percent-encoded.
        case keyPrefix(named: String)
    }
    
    /// The suite of an app scope.
    enum AppScope: Hashable, Sendable {
        /// `UserDefaults.standard`.
        case standard
        /// The suite with this name.
        /// - Warning: On macOS without App Sandbox, every app of the user that uses this name shares the suite.
        case suite(named: String)
    }
    
    /// The suite of the values, which decides who can read them.
    enum Scope: KeyValueDataStorageScope {
        /// `UserDefaults.standard` or a named suite.
        case app(AppScope, namespace: Namespace? = nil)
        /// The App Group's suite, shared by every app and extension in the group.
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
