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
    /// `kSecAttrService`; `nil` for items without one.
    func service(for scope: KeychainStorage.Scope) -> String?

    /// `kSecAttrAccessGroup`; `nil` for the app's default.
    func accessGroup(for scope: KeychainStorage.Scope) -> String?

    /// `kSecAttrAccount`.
    func account(forKey key: String, in scope: KeychainStorage.Scope) -> String
}

// MARK: - DefaultKeychainLocator

open class DefaultKeychainLocator: KeychainLocator {
    public init() { }

    open func service(for scope: KeychainStorage.Scope) -> String? {
        switch scope.namespace {
        case let .service(name)?:   return name
        case nil:                   return nil
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
}
