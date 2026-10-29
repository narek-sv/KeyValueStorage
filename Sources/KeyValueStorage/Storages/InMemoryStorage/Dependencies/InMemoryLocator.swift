//
//  InMemoryLocator.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation

// MARK: - InMemoryLocator

/// - Note: `clear()` empties the scope's whole bucket, so a custom locator gives each scope its own.
public protocol InMemoryLocator {
    /// `nil` for the unnamed bucket.
    func bucket(for scope: InMemoryStorage.Scope) -> String?

    func storedKey(forKey key: String, in scope: InMemoryStorage.Scope) -> String
}

// MARK: - DefaultInMemoryLocator

open class DefaultInMemoryLocator: InMemoryLocator {
    public init() { }

    open func bucket(for scope: InMemoryStorage.Scope) -> String? {
        switch scope.namespace {
        case let .bucket(name)?:    return name
        case nil:                   return nil
        }
    }

    open func storedKey(forKey key: String, in scope: InMemoryStorage.Scope) -> String {
        key
    }
}
