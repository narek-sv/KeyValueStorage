//
//  UnifiedStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 11.12.23.
//

// MARK: - UnifiedStorage

/// One API for every storage, which reaches each value through its `Entry`: its storage type, scope and key.
///
/// - It's safe to call from any thread, task or actor, and calls on storages of different types or scopes never wait for
///   each other; only `move`, `update` and `close` hold their scopes, and calls in them wait until they're done. Only
///   `Sendable` storages compile in entries (`UnifiedStorable`): the built-in storages are thread-safe, and
///   `IsolatedDataStorage` makes any other one shareable.
/// - It creates one storage per storage type and scope, on first use, through its factory, and keeps it until
///   `close(storage:forScope:)` lets go of it, or until it's deallocated: close a scope the app is done with, such as a
///   SQLite scope per account, to close its database.
/// - Reach each scope through one storage type: `FileStorage` and `IsolatedDataStorage<FileStorage>` are two storages over
///   the same files, so a `move` or an `update` through one doesn't hold the other's calls, a `close` closes only its own,
///   and each one's observers get only the changes made through it.
/// - Cancelling a call doesn't cancel its storage's creation, which concurrent calls share.
/// - When its factory makes a storage observable, the changes made through it are published; see `ObservableStorage`.
/// - Warning: Don't call it from inside its own storages, coders, factory or `ObservableStorage` subclasses: such a call can
///   wait for a `move` or an `update` that waits for the call it's made in, and never return.
public final class UnifiedStorage: Sendable {

    // MARK: Properties

    /// Each storage type and scope's storage, and the calls, moves, updates and closes in it.
    let scopes: Scopes

    // MARK: Initializers

    public init(factory: any UnifiedStorageFactory) {
        scopes = Scopes(factory: factory)
    }

    public init(observable: Bool = false) {
        scopes = Scopes(factory: observable ? ObservableUnifiedStorageFactory() : DefaultUnifiedStorageFactory())
    }

    // MARK: Main Functionality

    public func fetch<Storage: UnifiedStorable, Value: CodingValue>(_ entry: Entry<Storage, Value>) async throws(CodingStorageError<Storage>) -> Value? {
        try await scopes.withSharedAccess(to: entry.scope) { (storage: ScopeStorage<Storage>) throws(CodingStorageError<Storage>) in
            try await storage.fetch(forKey: .init(key: entry.key))
        }
    }

    public func save<Storage: UnifiedStorable, Value: CodingValue>(_ value: Value, to entry: Entry<Storage, Value>) async throws(CodingStorageError<Storage>) {
        try await scopes.withSharedAccess(to: entry.scope) { (storage: ScopeStorage<Storage>) throws(CodingStorageError<Storage>) in
            try await storage.save(value, forKey: .init(key: entry.key))
        }
    }

    /// Saves `value`, or deletes the stored one if `nil`, through the storage's `set`.
    public func set<Storage: UnifiedStorable, Value: CodingValue>(_ value: Value?, to entry: Entry<Storage, Value>) async throws(CodingStorageError<Storage>) {
        try await scopes.withSharedAccess(to: entry.scope) { (storage: ScopeStorage<Storage>) throws(CodingStorageError<Storage>) in
            try await storage.set(value, forKey: .init(key: entry.key))
        }
    }

    public func delete<Storage: UnifiedStorable, Value: CodingValue>(_ entry: Entry<Storage, Value>) async throws(CodingStorageError<Storage>) {
        try await scopes.withSharedAccess(to: entry.scope) { (storage: ScopeStorage<Storage>) throws(CodingStorageError<Storage>) in
            try await storage.delete(forKey: CodingStorageKey<Storage, Value>(key: entry.key))
        }
    }

    /// Removes every value of the storage type's scope.
    public func clear<Storage: UnifiedStorable>(storage _: Storage.Type, forScope scope: Storage.Scope = .default) async throws(CodingStorageError<Storage>) {
        try await scopes.withSharedAccess(to: scope) { (storage: ScopeStorage<Storage>) throws(CodingStorageError<Storage>) in
            try await storage.clear()
        }
    }

    /// Moves the value at the entry's key from `scope` into the entry's own scope, such as when a scope's protection or
    /// namespace changes: saves it there, unless a value is there already, then removes it from `scope`.
    ///
    /// - Calls through this `UnifiedStorage` in either scope wait until the move is done, and the move waits for those
    ///   already running, so none of them sees it half done.
    /// - The value is never lost: it's removed from `scope` only once it's saved, and a failed or interrupted move is
    ///   finished by calling it again.
    /// - Warning: Other `UnifiedStorage` instances, storages used directly and other processes, such as app extensions,
    ///   don't wait: move values before they use them, for example at launch.
    /// - Warning: Scopes that resolve to one place, such as File or SQLite App Group ids that differ only in case on macOS, or
    ///   two scopes a custom locator maps to one place, aren't two copies: the move takes the value for one already in the
    ///   target, and deletes it.
    public func move<Storage: UnifiedStorable, Value: CodingValue>(_ entry: Entry<Storage, Value>, from scope: Storage.Scope) async throws(CodingStorageError<Storage>) {
        guard scope != entry.scope else {
            return
        }

        try await scopes.withExclusiveAccess(to: scope, entry.scope) {
            (source: ScopeStorage<Storage>, target: ScopeStorage<Storage>) throws(CodingStorageError<Storage>) in
            let codingKey = CodingStorageKey<Storage, Value>(key: entry.key)
            guard let value = try await source.fetch(forKey: codingKey) else {
                return
            }

            // A value already there is newer: saved since, or by an earlier move that couldn't remove the old one
            if try await target.fetch(forKey: codingKey) == nil {
                try await target.save(value, forKey: codingKey)
            }

            try await source.delete(forKey: codingKey)
        }
    }

    /// Saves what `transform` makes of the entry's value, or deletes the value for `nil`, as one step, such as to count:
    /// calls through this `UnifiedStorage` in the entry's scope wait until it's done, and it waits for those already running.
    /// - Parameter transform: Gets the stored value, or `nil` if there's none. It can't `await` or throw, so it never waits
    ///   for this storage; work out what can fail before updating.
    /// - Returns: The value `transform` made, now stored.
    /// - Warning: Other `UnifiedStorage` instances, storages used directly and other processes, such as app extensions,
    ///   don't wait, so their saves can come between the read and the write.
    /// - Warning: `transform` gets `nil` whenever the storage reads none, as User Defaults does before the first unlock after
    ///   a restart: don't update its values then, or the result can replace the value it couldn't read.
    @discardableResult
    public func update<Storage: UnifiedStorable, Value: CodingValue>(
        _ entry: Entry<Storage, Value>,
        _ transform: (Value?) -> Value?
    ) async throws(CodingStorageError<Storage>) -> Value? {
        try await scopes.withExclusiveAccess(to: entry.scope) { (storage: ScopeStorage<Storage>) throws(CodingStorageError<Storage>) in
            let codingKey = CodingStorageKey<Storage, Value>(key: entry.key)
            let updated = transform(try await storage.fetch(forKey: codingKey))
            try await storage.set(updated, forKey: codingKey)
            return updated
        }
    }

    /// Lets go of the storage of the scope, so the next call creates a new one, such as to close the database of a SQLite
    /// scope the app is done with. The values stay.
    ///
    /// - Calls through this `UnifiedStorage` in the scope wait until it's done, and it waits for those already running.
    /// - The storage is released before it returns, once nothing else keeps it: a factory that keeps its own reference keeps
    ///   it open.
    public func close<Storage: UnifiedStorable>(storage _: Storage.Type, forScope scope: Storage.Scope = .default) async {
        await scopes.withExclusiveAccess(closing: scope, of: Storage.self)
    }

    // MARK: Observation

    /// Changes are delivered on the thread that makes them; see `ObservableStorage`.
    /// - Parameter includingCurrentValue: Whether the publisher first emits the stored value, or `nil` if there's none: the
    ///   value this call reads, or a change published since.
    /// - Returns: `nil` if the factory doesn't make the entry's storage observable.
    /// - Warning: In the Swift 6 language mode, a `sink` written in `@MainActor` code crashes when a save made off the main
    ///   actor calls it: put `receive(on: DispatchQueue.main)` before it.
    public func publisher<Storage: UnifiedStorable, Value: CodingValue>(for entry: Entry<Storage, Value>, includingCurrentValue: Bool = true)
    async throws(CodingStorageError<Storage>) -> ValuePublisher<Value?>? {
        try await scopes.withSharedAccess(to: entry.scope) { (storage: ScopeStorage<Storage>) throws(CodingStorageError<Storage>) in
            try await storage.observable?.publisher(
                forKey: .init(key: entry.key),
                includingCurrentValue: includingCurrentValue
            )
        }
    }

    /// The stream resumes on the executor of the task that iterates it; see `ObservableStorage`.
    /// - Parameter includingCurrentValue: Whether the stream starts with the stored value, or `nil` if there's none: the
    ///   value this call reads, or a change published since.
    /// - Parameter bufferingPolicy: What the stream keeps of the values its consumer hasn't read yet: every one with
    ///   `.unbounded`, held in memory while the consumer falls behind, or only the latest with `.bufferingNewest(1)`.
    /// - Returns: `nil` if the factory doesn't make the entry's storage observable.
    public func stream<Storage: UnifiedStorable, Value: CodingValue>(
        for entry: Entry<Storage, Value>,
        includingCurrentValue: Bool = true,
        bufferingPolicy: AsyncStream<Value?>.Continuation.BufferingPolicy = .unbounded
    ) async throws(CodingStorageError<Storage>) -> AsyncStream<Value?>? {
        try await scopes.withSharedAccess(to: entry.scope) { (storage: ScopeStorage<Storage>) throws(CodingStorageError<Storage>) in
            try await storage.observable?.stream(
                forKey: .init(key: entry.key),
                includingCurrentValue: includingCurrentValue,
                bufferingPolicy: bufferingPolicy
            )
        }
    }
}
