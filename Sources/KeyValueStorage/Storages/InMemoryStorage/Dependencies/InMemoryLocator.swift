//
//  InMemoryLocator.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation

// MARK: - InMemoryLocator

/// - Note: `clear()` empties the scope's whole bucket, so a custom locator gives each scope its own.
public protocol InMemoryLocator: Sendable {
    func bucket(for scope: InMemoryStorage.Scope) -> String

    func storedKey(forKey key: InMemoryStorage.Key, in scope: InMemoryStorage.Scope) -> String
}

// MARK: - DefaultInMemoryLocator

/// The bucket is the namespace, and the stored key the key, both as they are.
/// - Warning: Subclasses inherit `Sendable`: their own state must be thread-safe too.
open class DefaultInMemoryLocator: InMemoryLocator, @unchecked Sendable {
    public init() { }

    open func bucket(for scope: InMemoryStorage.Scope) -> String {
        switch scope {
        case let .own(namespace):   return namespace.string
        }
    }

    open func storedKey(forKey key: InMemoryStorage.Key, in scope: InMemoryStorage.Scope) -> String {
        key.string
    }
}
