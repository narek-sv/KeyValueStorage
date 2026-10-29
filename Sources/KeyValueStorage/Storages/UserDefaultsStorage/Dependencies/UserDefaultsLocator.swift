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

/// Stores a namespace's keys as `<namespace>/<key>` and root keys as they are, with `%` and `/` percent-encoded
/// in the namespace and in root keys, so a root key never contains `/` and never equals a namespace's.
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
        Self.storedKey(forKey: key, in: scope)
    }

    open func key(forStoredKey storedKey: String, in scope: UserDefaultsStorage.Scope) -> String? {
        let key: String?
        switch scope.namespace {
        case let .keyPrefix(name)?:
            let prefix = Self.escaped(name) + "/"
            // Bytes, not characters: a key can start with a combining mark, which joins the `/` before it
            key = storedKey.utf8.starts(with: prefix.utf8) ? String(decoding: storedKey.utf8.dropFirst(prefix.utf8.count), as: UTF8.self) : nil
        case nil:
            key = Self.unescaped(storedKey)
        }

        // Decoding alone also accepts stored keys the encoding never writes, such as `a/b` for a root key
        guard let key, Self.storedKey(forKey: key, in: scope).utf8.elementsEqual(storedKey.utf8) else {
            return nil
        }

        return key
    }

    // MARK: Helpers

    private static func storedKey(forKey key: String, in scope: UserDefaultsStorage.Scope) -> String {
        switch scope.namespace {
        case let .keyPrefix(name)?: return escaped(name) + "/" + key
        case nil:                   return escaped(key)
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

    private static func unescaped(_ name: String) -> String {
        var bytes = [UInt8]()
        var rest = Substring(name).utf8
        while let byte = rest.popFirst() {
            if byte == UInt8(ascii: "%"), rest.starts(with: "25".utf8) {
                bytes.append(UInt8(ascii: "%"))
                rest.removeFirst(2)
            } else if byte == UInt8(ascii: "%"), rest.starts(with: "2F".utf8) {
                bytes.append(UInt8(ascii: "/"))
                rest.removeFirst(2)
            } else {
                bytes.append(byte)
            }
        }

        return String(decoding: bytes, as: UTF8.self)
    }
}
