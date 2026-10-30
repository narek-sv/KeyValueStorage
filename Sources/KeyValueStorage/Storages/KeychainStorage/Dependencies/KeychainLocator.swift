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
    func account(forKey key: KeychainStorage.Key, in scope: KeychainStorage.Scope) -> String
}

// MARK: - DefaultKeychainLocator

/// Services are `<app>:<namespace>:<protection>` for `.own`, `<app>` being the bundle ID or, without one, the process name,
/// and `<group>/<namespace>/<protection>` for `.appGroup`, with `%`, `/` and `:` percent-encoded in each name. So no two
/// scopes share a service, which matters because `.own` queries reach every access group the app has, and apps can share one.
/// `.iCloud` uses its owner's services, for synced items, which the other scopes' queries never match.
open class DefaultKeychainLocator: KeychainLocator {
    public init() { }

    // MARK: App Identifier

    /// `OwnIdentity.identifier`.
    open var ownIdentifier: String {
        OwnIdentity.identifier
    }

    // MARK: Names

    open func service(for scope: KeychainStorage.Scope) -> String {
        switch scope {
        case let .own(protection, namespace):
            return ownService(namespace, Self.name(for: protection))
        case let .appGroup(groupId, protection, namespace):
            return Self.groupService(groupId, namespace, Self.name(for: protection))
        case let .iCloud(.own, protection, namespace):
            return ownService(namespace, Self.name(for: protection))
        case let .iCloud(.appGroup(groupId), protection, namespace):
            return Self.groupService(groupId, namespace, Self.name(for: protection))
        }
    }

    open func accessGroup(for scope: KeychainStorage.Scope) -> String? {
        switch scope {
        case .own, .iCloud(.own, _, _):
            return nil
        case let .appGroup(groupId, _, _), let .iCloud(.appGroup(groupId), _, _):
            return groupId
        }
    }

    open func account(forKey key: KeychainStorage.Key, in scope: KeychainStorage.Scope) -> String {
        key.string
    }

    // MARK: Helpers

    private func ownService(_ namespace: KeychainStorage.Namespace, _ protection: String) -> String {
        Self.escaped(ownIdentifier) + ":" + Self.escaped(namespace.string) + ":" + protection
    }

    private static func groupService(_ groupId: String, _ namespace: KeychainStorage.Namespace, _ protection: String) -> String {
        escaped(groupId) + "/" + escaped(namespace.string) + "/" + protection
    }

    private static func name(for protection: KeychainStorage.Protection) -> String {
        switch protection {
        case .untilFirstUnlock:                 return "u"
        case .untilFirstUnlockThisDeviceOnly:   return "ud"
        case .whileLocked:                      return "w"
        case .whileLockedThisDeviceOnly:        return "wd"
        case .whileLockedOrWithoutPasscode:     return "p"
        }
    }

    // Local queries never match synced items, so the two share letters
    private static func name(for protection: KeychainStorage.SyncedProtection) -> String {
        switch protection {
        case .untilFirstUnlock: return "u"
        case .whileLocked:      return "w"
        }
    }

    // Bytes, because Foundation's `replacingOccurrences` skips a `/` that carries a combining mark
    private static func escaped(_ name: String) -> String {
        var escaped = [UInt8]()
        for byte in name.utf8 {
            switch byte {
            case UInt8(ascii: "%"): escaped += Array("%25".utf8)
            case UInt8(ascii: "/"): escaped += Array("%2F".utf8)
            case UInt8(ascii: ":"): escaped += Array("%3A".utf8)
            default:                escaped.append(byte)
            }
        }

        return String(decoding: escaped, as: UTF8.self)
    }
}
