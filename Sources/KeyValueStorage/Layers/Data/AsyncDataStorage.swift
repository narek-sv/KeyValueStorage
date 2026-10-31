//
//  AsyncDataStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

import Foundation

// MARK: - AsyncDataStorage

/// A storage whose operations may suspend, such as one backed by a server.
/// - Note: Every `DataStorage` is one too, with its synchronous methods.
/// - Note: No extension members: an `async` member here would win over a synchronous one of the same name inside `async` code,
///   so calls on synchronous storages would need `await`.
public protocol AsyncDataStorage {
    associatedtype Key: Hashable & Sendable
    associatedtype Scope: DataStorageScope
    associatedtype Error: Swift.Error & Sendable

    var scope: Scope { get }

    init(scope: Scope) async throws(Error)

    func fetch(forKey key: Key) async throws(Error) -> Data?
    func save(_ value: Data, forKey key: Key) async throws(Error)
    func delete(forKey key: Key) async throws(Error)
    func clear() async throws(Error)
}

// MARK: - DataStorageScope

/// - Warning: `.own` belongs to the bundle ID: builds that share one share values, and unit tests hosted in an app use the app's,
///   so a test's `clear()` empties the app's data on that device. Give tests a namespace of their own.
public protocol DataStorageScope: Hashable & Sendable {
    static var `default`: Self { get }
}

// MARK: - DataStorageScope + Defaults

public extension DataStorageScope {
    /// Every `default` scope's namespace.
    /// - Warning: Shared by everything in the app that uses a `default` scope.
    static var defaultNamespace: ExactString {
        "KeyValueStorage"
    }
}
