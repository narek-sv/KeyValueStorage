//
//  IsolatedKeyValueDataStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.10.26.
//

import Foundation

// MARK: - IsolatedKeyValueDataStorage

/// Isolates a synchronous storage in an actor, so tasks and threads can share it; its operations run one at a time.
/// - Note: The wrapped storage's calls block the actor's thread for as long as they take, such as a file read.
public actor IsolatedKeyValueDataStorage<Wrapped: KeyValueDataStorage>: AsyncKeyValueDataStorage {
    public typealias Key = Wrapped.Key
    public typealias Scope = Wrapped.Scope
    public typealias Error = Wrapped.Error

    // MARK: Properties

    public nonisolated let scope: Scope
    private let wrapped: Wrapped

    // MARK: Initializers

    /// - Parameter wrapped: Given up by the caller, so nothing else reaches it unsynchronized.
    public init(_ wrapped: sending Wrapped) {
        self.scope = wrapped.scope
        self.wrapped = wrapped
    }

    public nonisolated init(scope: Scope) async throws(Error) {
        // Unsafe only to the compiler: nothing else holds the new storage, but `Wrapped.Type` can't be `SendableMetatype` before Swift 6.2
        nonisolated(unsafe) let wrapped = try await Wrapped(scope: scope)
        self.init(wrapped)
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) throws(Error) -> Data? {
        try wrapped.fetch(forKey: key)
    }

    public func save(_ value: Data, forKey key: Key) throws(Error) {
        try wrapped.save(value, forKey: key)
    }

    public func delete(forKey key: Key) throws(Error) {
        try wrapped.delete(forKey: key)
    }

    public func clear() throws(Error) {
        try wrapped.clear()
    }

    /// Saves `value`, or deletes it if `nil`.
    public func set(_ value: Data?, forKey key: Key) throws(Error) {
        try wrapped.set(value, forKey: key)
    }

    /// Runs `body` on the actor with the wrapped storage, so several operations are one atomic step, such as read-modify-write.
    public func withStorage<T: Sendable, E: Swift.Error>(_ body: @Sendable (Wrapped) throws(E) -> T) throws(E) -> T {
        try body(wrapped)
    }
}
