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
    func suiteName(for scope: UserDefaultsStorage.Scope) throws(UserDefaultsStorage.Error) -> String

    func storedKey(forKey key: UserDefaultsStorage.Key, in scope: UserDefaultsStorage.Scope) -> String

    /// `nil` for stored keys no key of the scope produces.
    func key(forStoredKey storedKey: String, in scope: UserDefaultsStorage.Scope) -> UserDefaultsStorage.Key?
}

// MARK: - DefaultUserDefaultsLocator

/// `.own` uses the suite `<app>.KeyValueStorage`, `<app>` being the bundle ID, or the process name without one, in
/// `DefaultFileLocator`'s encoding; `.appGroup` uses the group's suite. Keys are stored as `<namespace>!/<key>`, with `%` and
/// `/` percent-encoded in the namespace: the `!` marks the library's keys in a suite other code also writes to.
/// - Note: A subclass that changes stored keys overrides both key methods.
open class DefaultUserDefaultsLocator: UserDefaultsLocator {
    /// Every suite reads the global domain, so a suite of it would reach every scope.
    private static let globalDomainNames: Set = ["NSGlobalDomain", ".GlobalPreferences", "kCFPreferencesAnyApplication", "Apple Global Domain"]
    private static let reservedBytes: Set = [UInt8(ascii: "%"), UInt8(ascii: "/")]

    public init() { }

    // MARK: App Identifier

    /// `OwnIdentity.identifier`.
    open var ownIdentifier: String {
        OwnIdentity.identifier
    }

    // MARK: Names

    open func suiteName(for scope: UserDefaultsStorage.Scope) throws(UserDefaultsStorage.Error) -> String {
        // Portable, so identifiers that differ only in case get two suite files
        let ownSuiteName = ownIdentifier.portableName + ".KeyValueStorage"
        switch scope {
        case .own:
            return ownSuiteName
        case let .appGroup(groupId, _):
            guard !groupId.isEmpty, !Self.globalDomainNames.contains(groupId), groupId != ownSuiteName else {
                throw .invalidSuiteName(groupId)
            }

            return groupId
        }
    }

    open func storedKey(forKey key: UserDefaultsStorage.Key, in scope: UserDefaultsStorage.Scope) -> String {
        Self.prefix(for: scope) + key.string
    }

    open func key(forStoredKey storedKey: String, in scope: UserDefaultsStorage.Scope) -> UserDefaultsStorage.Key? {
        storedKey.droppingExactPrefix(Self.prefix(for: scope)).map { .init($0) }
    }

    // MARK: Helpers

    /// The namespace has no `/` once escaped, so the first `/` always ends it.
    private static func prefix(for scope: UserDefaultsStorage.Scope) -> String {
        switch scope {
        case let .own(namespace), let .appGroup(_, namespace):
            return namespace.string.percentEscaping(reservedBytes) + "!/"
        }
    }
}
