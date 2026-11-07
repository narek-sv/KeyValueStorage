//
//  UserDefaultsLocatorStub.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation
@testable import KeyValueStorage

/// Fixed names, to check that the storage uses exactly what its locator returns; records each call.
/// Unchecked: used from one test at a time.
final class UserDefaultsLocatorStub: UserDefaultsLocator, @unchecked Sendable {
    enum Call: Equatable {
        case suiteName(UserDefaultsStorage.Scope)
        case storedKey(UserDefaultsStorage.Key, UserDefaultsStorage.Scope)
        case key(String, UserDefaultsStorage.Scope)
    }

    var suiteName = "located"
    var suiteNameError: UserDefaultsStorage.Error?
    /// The stored keys the locator claims, and their keys.
    var keys = [String: UserDefaultsStorage.Key]()
    private(set) var calls = [Call]()

    func suiteName(for scope: UserDefaultsStorage.Scope) throws(UserDefaultsStorage.Error) -> String {
        calls.append(.suiteName(scope))
        if let suiteNameError {
            throw suiteNameError
        }

        return suiteName
    }

    func storedKey(forKey key: UserDefaultsStorage.Key, in scope: UserDefaultsStorage.Scope) -> String {
        calls.append(.storedKey(key, scope))
        return "located-\(key)"
    }

    func key(forStoredKey storedKey: String, in scope: UserDefaultsStorage.Scope) -> UserDefaultsStorage.Key? {
        calls.append(.key(storedKey, scope))
        return keys[storedKey]
    }
}
