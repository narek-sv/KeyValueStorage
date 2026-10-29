//
//  KeychainLocator.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation

// MARK: - KeychainLocator

/// - Note: `clear()` removes every item of the scope's service and access group, so a custom locator gives each scope its own.
public protocol KeychainLocator {
    /// `kSecAttrService`.
    func service(for scope: KeychainStorage.Scope) -> String

    /// `kSecAttrAccessGroup`; `nil` for the app's default.
    func accessGroup(for scope: KeychainStorage.Scope) -> String?

    /// `kSecAttrAccount`.
    func account(forKey key: String, in scope: KeychainStorage.Scope) -> String
}

// MARK: - DefaultKeychainLocator

/// The namespace is the service, `""` at the root, and an App Group's service is `<group>/<namespace>`, with `%` and `/`
/// percent-encoded in both and the empty name `%`. So an app scope's service never contains `/` and never equals a group's,
/// which matters because an app scope's queries reach every access group the app has.
open class DefaultKeychainLocator: KeychainLocator {
    public init() { }

    open func service(for scope: KeychainStorage.Scope) -> String {
        let namespace = scope.namespace.map(Self.name(of:)) ?? ""
        switch scope {
        case .app:                          return namespace
        case let .appGroup(groupId, _):     return Self.escaped(groupId) + "/" + namespace
        }
    }

    open func accessGroup(for scope: KeychainStorage.Scope) -> String? {
        switch scope {
        case .app:                          return nil
        case let .appGroup(groupId, _):     return groupId
        }
    }

    open func account(forKey key: String, in scope: KeychainStorage.Scope) -> String {
        key
    }

    // MARK: Helpers

    private static func name(of namespace: KeychainStorage.Namespace) -> String {
        switch namespace {
        case let .service(name):    return escaped(name)
        }
    }

    // Bytes, because Foundation's `replacingOccurrences` skips a `/` that carries a combining mark
    private static func escaped(_ name: String) -> String {
        guard !name.isEmpty else {
            return "%"
        }

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
}
