//
//  InMemoryLocatorStub.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation
@testable import KeyValueStorage

/// Fixed names, to check that the storage uses exactly what its locator returns; records each call.
final class InMemoryLocatorStub: InMemoryLocator {
    enum Call: Equatable {
        case bucket(InMemoryStorage.Scope)
        case storedKey(InMemoryStorage.Key, InMemoryStorage.Scope)
    }

    private(set) var calls = [Call]()

    func bucket(for scope: InMemoryStorage.Scope) -> String {
        calls.append(.bucket(scope))
        return "located-bucket"
    }

    func storedKey(forKey key: InMemoryStorage.Key, in scope: InMemoryStorage.Scope) -> String {
        calls.append(.storedKey(key, scope))
        return "located-\(key)"
    }
}
