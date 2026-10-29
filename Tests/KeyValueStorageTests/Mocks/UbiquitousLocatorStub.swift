//
//  UbiquitousLocatorStub.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation
@testable import KeyValueStorage

/// Fixed names, to check that the storage uses exactly what its locator returns; records each call.
@available(watchOS 9.0, *)
final class UbiquitousLocatorStub: UbiquitousLocator {
    enum Call: Equatable {
        case storedKey(String, UbiquitousStorage.Scope)
        case key(String, UbiquitousStorage.Scope)
    }

    var storedKeyError: UbiquitousStorage.Error?
    /// The stored keys the locator claims, and their keys.
    var keys = [String: String]()
    private(set) var calls = [Call]()

    func storedKey(forKey key: String, in scope: UbiquitousStorage.Scope) throws(UbiquitousStorage.Error) -> String {
        calls.append(.storedKey(key, scope))
        if let storedKeyError {
            throw storedKeyError
        }

        return "located-\(key)"
    }

    func key(forStoredKey storedKey: String, in scope: UbiquitousStorage.Scope) -> String? {
        calls.append(.key(storedKey, scope))
        return keys[storedKey]
    }
}
