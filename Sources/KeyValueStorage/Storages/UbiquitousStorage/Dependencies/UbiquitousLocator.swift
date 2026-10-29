//
//  UbiquitousLocator.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation

// MARK: - UbiquitousLocator

/// A custom locator must:
/// - keep stored keys within 128 UTF-16 code units: the store raises an Objective-C exception, a crash, for longer ones;
/// - make `key(forStoredKey:in:)` the exact inverse of `storedKey(forKey:in:)`, or `clear()` leaves values behind.
@available(watchOS 9.0, *)
public protocol UbiquitousLocator {
    /// `.invalidKey` over 128 UTF-16 code units.
    func storedKey(forKey key: String, in scope: UbiquitousStorage.Scope) throws(UbiquitousStorage.Error) -> String

    /// `nil` for stored keys no key of the scope produces.
    func key(forStoredKey storedKey: String, in scope: UbiquitousStorage.Scope) -> String?
}

// MARK: - DefaultUbiquitousLocator

/// Stores a namespace's keys as `<namespace>/<key>` and root keys as they are, with `%` and `/` percent-encoded
/// in the namespace and in root keys, so a root key never contains `/` and never equals a namespace's.
/// - Note: A subclass that changes stored keys overrides both key methods.
@available(watchOS 9.0, *)
open class DefaultUbiquitousLocator: UbiquitousLocator {
    private static let maximumKeyLength = 128

    public init() { }

    open func storedKey(forKey key: String, in scope: UbiquitousStorage.Scope) throws(UbiquitousStorage.Error) -> String {
        try Self.storedKey(forKey: key, in: scope)
    }

    open func key(forStoredKey storedKey: String, in scope: UbiquitousStorage.Scope) -> String? {
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
        guard let key, let encoded = try? Self.storedKey(forKey: key, in: scope), encoded.utf8.elementsEqual(storedKey.utf8) else {
            return nil
        }

        return key
    }

    // MARK: Helpers

    private static func storedKey(forKey key: String, in scope: UbiquitousStorage.Scope) throws(UbiquitousStorage.Error) -> String {
        let storedKey: String
        switch scope.namespace {
        case let .keyPrefix(name)?: storedKey = escaped(name) + "/" + key
        case nil:                   storedKey = escaped(key)
        }

        guard storedKey.utf16.count <= maximumKeyLength else {
            throw .invalidKey(key)
        }

        return storedKey
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
