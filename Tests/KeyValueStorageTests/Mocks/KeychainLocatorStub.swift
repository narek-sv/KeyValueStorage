//
//  KeychainLocatorStub.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation
@testable import KeyValueStorage

/// Fixed names, to check that the storage uses exactly what its locator returns; records each call.
/// Unchecked: used from one test at a time.
final class KeychainLocatorStub: KeychainLocator, @unchecked Sendable {
    enum Call: Equatable {
        case service(KeychainStorage.Scope)
        case accessGroup(KeychainStorage.Scope)
        case account(KeychainStorage.Key, KeychainStorage.Scope)
    }

    private(set) var calls = [Call]()

    func service(for scope: KeychainStorage.Scope) -> String {
        calls.append(.service(scope))
        return "located-service"
    }

    func accessGroup(for scope: KeychainStorage.Scope) -> String? {
        calls.append(.accessGroup(scope))
        return "located.group"
    }

    func account(forKey key: KeychainStorage.Key, in scope: KeychainStorage.Scope) -> String {
        calls.append(.account(key, scope))
        return "located-\(key)"
    }
}
