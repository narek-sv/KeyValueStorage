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
/// Unchecked: used from one test at a time.
final class UbiquitousLocatorStub: UbiquitousLocator, @unchecked Sendable {
    enum Call: Equatable {
        case storedKey(UbiquitousStorage.Key, UbiquitousStorage.Scope)
        case key(String, UbiquitousStorage.Scope)
    }

    var storedKeyError: UbiquitousStorage.Error?
    /// The stored keys the locator claims, and their keys.
    var keys = [String: UbiquitousStorage.Key]()
    private(set) var calls = [Call]()

    func storedKey(forKey key: UbiquitousStorage.Key, in scope: UbiquitousStorage.Scope) throws(UbiquitousStorage.Error) -> String {
        calls.append(.storedKey(key, scope))
        if let storedKeyError {
            throw storedKeyError
        }

        return "located-\(key)"
    }

    func key(forStoredKey storedKey: String, in scope: UbiquitousStorage.Scope) -> UbiquitousStorage.Key? {
        calls.append(.key(storedKey, scope))
        return keys[storedKey]
    }
}
