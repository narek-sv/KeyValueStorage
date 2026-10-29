//
//  UbiquitousLocator.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation

// MARK: - UbiquitousLocator

/// A custom locator must:
/// - keep stored keys within 128 UTF-16 code units, the store's limit;
/// - make `key(forStoredKey:in:)` the exact inverse of `storedKey(forKey:in:)`, or `clear()` leaves values behind.
@available(watchOS 9.0, *)
public protocol UbiquitousLocator {
    /// `.invalidKey` over 128 UTF-16 code units.
    func storedKey(forKey key: String, in scope: UbiquitousStorage.Scope) throws(UbiquitousStorage.Error) -> String

    /// `nil` for stored keys no key of the scope produces.
    func key(forStoredKey storedKey: String, in scope: UbiquitousStorage.Scope) -> String?
}

// MARK: - DefaultUbiquitousLocator

/// Stores a namespace's keys as `<namespace>/<key>`, with `%` and `/` in the namespace percent-encoded.
/// - Warning: Without a namespace, keys are stored as is, and the scope claims every key of the store.
/// - Note: A subclass that changes stored keys overrides both key methods.
@available(watchOS 9.0, *)
open class DefaultUbiquitousLocator: UbiquitousLocator {
    private static let maximumKeyLength = 128

    public init() { }

    open func storedKey(forKey key: String, in scope: UbiquitousStorage.Scope) throws(UbiquitousStorage.Error) -> String {
        let storedKey = Self.prefix(of: scope).map { $0 + key } ?? key
        guard storedKey.utf16.count <= Self.maximumKeyLength else {
            throw .invalidKey(key)
        }

        return storedKey
    }

    open func key(forStoredKey storedKey: String, in scope: UbiquitousStorage.Scope) -> String? {
        guard let prefix = Self.prefix(of: scope) else {
            return storedKey
        }

        return storedKey.hasPrefix(prefix) ? String(storedKey.dropFirst(prefix.count)) : nil
    }

    // MARK: Helpers

    private static func prefix(of scope: UbiquitousStorage.Scope) -> String? {
        switch scope.namespace {
        case let .keyPrefix(name)?:
            return name.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: "/", with: "%2F") + "/"
        case nil:
            return nil
        }
    }
}
