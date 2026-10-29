//
//  UserDefaultsLocatorStub.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation
@testable import KeyValueStorage

/// Fixed names, to check that the storage uses exactly what its locator returns; records each call.
final class UserDefaultsLocatorStub: UserDefaultsLocator {
    enum Call: Equatable {
        case suite(UserDefaultsStorage.Scope)
        case storedKey(String, UserDefaultsStorage.Scope)
        case key(String, UserDefaultsStorage.Scope)
    }

    var suite = UserDefaultsStorage.AppScope.suite(named: "located")
    /// The stored keys the locator claims, and their keys.
    var keys = [String: String]()
    private(set) var calls = [Call]()

    func suite(for scope: UserDefaultsStorage.Scope) -> UserDefaultsStorage.AppScope {
        calls.append(.suite(scope))
        return suite
    }

    func storedKey(forKey key: String, in scope: UserDefaultsStorage.Scope) -> String {
        calls.append(.storedKey(key, scope))
        return "located-\(key)"
    }

    func key(forStoredKey storedKey: String, in scope: UserDefaultsStorage.Scope) -> String? {
        calls.append(.key(storedKey, scope))
        return keys[storedKey]
    }
}
