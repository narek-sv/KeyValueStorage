//
//  UserDefaultsLocator.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation

// MARK: - UserDefaultsLocator

/// - Note: Make `key(forStoredKey:in:)` the exact inverse of `storedKey(forKey:in:)`, or `clear()` leaves values behind.
public protocol UserDefaultsLocator {
    func suite(for scope: UserDefaultsStorage.Scope) -> UserDefaultsStorage.AppScope

    func storedKey(forKey key: String, in scope: UserDefaultsStorage.Scope) -> String

    /// `nil` for stored keys no key of the scope produces.
    func key(forStoredKey storedKey: String, in scope: UserDefaultsStorage.Scope) -> String?
}

// MARK: - DefaultUserDefaultsLocator

/// Stores a namespace's keys as `<namespace>/<key>`, with `%` and `/` in the namespace percent-encoded.
/// - Warning: Without a namespace, keys are stored as is, and the scope claims every key of the suite.
/// - Note: A subclass that changes stored keys overrides both key methods.
open class DefaultUserDefaultsLocator: UserDefaultsLocator {
    public init() { }

    open func suite(for scope: UserDefaultsStorage.Scope) -> UserDefaultsStorage.AppScope {
        switch scope {
        case let .app(suite, _):            return suite
        case let .appGroup(groupId, _):     return .suite(named: groupId)
        }
    }

    open func storedKey(forKey key: String, in scope: UserDefaultsStorage.Scope) -> String {
        Self.prefix(of: scope).map { $0 + key } ?? key
    }

    open func key(forStoredKey storedKey: String, in scope: UserDefaultsStorage.Scope) -> String? {
        guard let prefix = Self.prefix(of: scope) else {
            return storedKey
        }

        return storedKey.hasPrefix(prefix) ? String(storedKey.dropFirst(prefix.count)) : nil
    }

    // MARK: Helpers

    private static func prefix(of scope: UserDefaultsStorage.Scope) -> String? {
        switch scope.namespace {
        case let .keyPrefix(name)?:
            return name.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: "/", with: "%2F") + "/"
        case nil:
            return nil
        }
    }
}
