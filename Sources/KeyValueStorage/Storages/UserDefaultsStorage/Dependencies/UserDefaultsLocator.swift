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
    private static let keptBytes = Set("abcdefghijklmnopqrstuvwxyz0123456789_-".utf8)
    private static let capitals = UInt8(ascii: "A")...UInt8(ascii: "Z")
    private static let lowercaseLetters = UInt8(ascii: "a")...UInt8(ascii: "z")
    private static let hexDigits = Array("0123456789abcdef".utf8)

    public init() { }

    // MARK: App Identifier

    /// `OwnIdentity.identifier`.
    open var ownIdentifier: String {
        OwnIdentity.identifier
    }

    // MARK: Names

    open func suiteName(for scope: UserDefaultsStorage.Scope) throws(UserDefaultsStorage.Error) -> String {
        let ownSuiteName = Self.encoded(ownIdentifier) + ".KeyValueStorage"
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
        let prefix = Self.prefix(for: scope)
        // Bytes, not characters: a key can start with a combining mark, which joins the `/` before it
        guard storedKey.utf8.starts(with: prefix.utf8) else {
            return nil
        }

        return .init(String(decoding: storedKey.utf8.dropFirst(prefix.utf8.count), as: UTF8.self))
    }

    // MARK: Helpers

    /// The namespace has no `/` once escaped, so the first `/` always ends it.
    private static func prefix(for scope: UserDefaultsStorage.Scope) -> String {
        switch scope {
        case let .own(namespace), let .appGroup(_, namespace):
            return escaped(namespace.string) + "!/"
        }
    }

    // Bytes, because Foundation's `replacingOccurrences` skips a `/` that carries a combining mark
    private static func escaped(_ name: String) -> String {
        var escaped = [UInt8]()
        for byte in name.utf8 {
            switch byte {
            case UInt8(ascii: "%"): escaped += Array("%25".utf8)
            case UInt8(ascii: "/"): escaped += Array("%2F".utf8)
            default:                escaped.append(byte)
            }
        }

        return String(decoding: escaped, as: UTF8.self)
    }

    /// `DefaultFileLocator`'s encoding, so identifiers that differ only in case get two suite files.
    private static func encoded(_ name: String) -> String {
        guard !name.isEmpty else {
            return "%"
        }

        var encoded = [UInt8]()
        for byte in name.utf8 {
            if keptBytes.contains(byte) {
                encoded.append(byte)
            } else if capitals.contains(byte) {
                encoded += [UInt8(ascii: "!"), byte - capitals.lowerBound + lowercaseLetters.lowerBound]
            } else {
                encoded += [UInt8(ascii: "%"), hexDigits[Int(byte >> 4)], hexDigits[Int(byte & 0x0F)]]
            }
        }

        return String(decoding: encoded, as: UTF8.self)
    }
}
