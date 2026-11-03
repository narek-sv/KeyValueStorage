//
//  ObservableStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.10.26.
//

import Combine
import Foundation

// MARK: - ObservableStorage

/// A coding storage that publishes the changes made through it.
///
/// - Changes are delivered on the thread that makes them, right after the write succeeds.
///   Use `receive(on: DispatchQueue.main)`, or hop to the main actor, before updating UI.
///   Streams resume on the executor of the task that iterates them.
/// - Every instance of a storage type and scope publishes to the others' observers, in this process.
///   Changes made otherwise aren't published: through a plain coding storage, by other processes (such as app extensions),
///   on other devices, or directly to `UserDefaults`, the keychain or files.
/// - An observer sees only the values saved with its own value type.
/// - Two calls that save one key at once may deliver their values out of order.
/// - Subscribers run inside the save, and other saves of the key wait for them: keep them short, and move slow work off with
///   `receive(on:)` or a stream. A subscriber that waits for another save of the same key never returns.
/// - While a key is observed, its latest change stays in memory, and each publisher keeps the value it read.
/// - Warning: In the Swift 6 language mode, a closure written in `@MainActor` code, as all code is in a target whose default
///   actor isolation is `MainActor`, crashes when it's called off the main thread: put `receive(on: DispatchQueue.main)`
///   before such a `sink`, or iterate a stream from the main actor.
/// - Warning: Subclasses inherit `Sendable`: their own state must be thread-safe too.
open class ObservableStorage<Storage: AsyncDataStorage & Sendable>: @unchecked Sendable {
    public typealias Error = CodingStorageError<Storage>

    // MARK: Properties

    private let storage: AsyncCodingStorage<Storage>
    private let registry = ObservationRegistry.shared
    private let scopeID: ObservationRegistry.ScopeID

    public var scope: Storage.Scope {
        storage.scope
    }

    // MARK: Initializers

    public init(_ storage: AsyncCodingStorage<Storage>) {
        self.storage = storage
        self.scopeID = .init(storageType: ObjectIdentifier(Storage.self), scope: AnyHashable(storage.scope))
    }

    // MARK: Main Functionality

    open func fetch<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>) async throws(Error) -> Value? {
        try await storage.fetch(forKey: key)
    }

    open func save<Value: CodingValue>(_ value: Value, forKey key: CodingStorageKey<Storage, Value>) async throws(Error) {
        try await storage.save(value, forKey: key)
        registry.observation(forKey: key, in: scopeID)?.change(to: value)
    }

    /// Saves `value`, or deletes the stored one if `nil`, through the storage's `set`, then publishes it.
    /// - Note: It doesn't call `save` or `delete`: a subclass that changes them changes this too.
    open func set<Value: CodingValue>(_ value: Value?, forKey key: CodingStorageKey<Storage, Value>) async throws(Error) {
        try await storage.set(value, forKey: key)
        registry.observation(forKey: key, in: scopeID)?.change(to: value)
    }

    open func delete<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>) async throws(Error) {
        try await storage.delete(forKey: key)
        registry.observation(forKey: key, in: scopeID)?.change(to: nil)
    }

    /// Every observed key of the scope gets `nil`.
    /// - Note: Only when the storage's `clear()` succeeds: when it throws, no observer is told, even about values it removed
    ///   before failing, such as those a file storage's `.clearIncomplete` doesn't list.
    open func clear() async throws(Error) {
        try await storage.clear()
        for observation in registry.observations(in: scopeID) {
            observation.change(to: nil)
        }
    }

    // MARK: Observation

    /// - Parameter includingCurrentValue: Whether the publisher first emits the stored value, or `nil` if there's none: the
    ///   value this call reads, or a change published since. Reading it can throw, for example when the stored data can't be decoded.
    open func publisher<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>,
                                            includingCurrentValue: Bool = true) async throws(Error) -> ValuePublisher<Value?> {
        let scopeID = scopeID
        let observation = registry.register(key, in: scopeID)
        let token = ObservationToken { [registry] in
            registry.release(observation, forKey: key, in: scopeID)
        }

        // The subject replays the latest change on subscription, so dropping it leaves only later changes, never `nil`
        guard includingCurrentValue else {
            return ValuePublisher(observation.subject
                .dropFirst()
                .map { change in
                    withExtendedLifetime(token) { change?.value as? Value }
                }
                .eraseToAnyPublisher())
        }

        // Every publisher reads for itself: changes no observation sees can make an earlier publisher's value outdated.
        // The version comes first, so a change published while reading, or before subscribing, wins over the value read
        let version = observation.version
        let value = try await fetch(forKey: key)
        return ValuePublisher(observation.subject
            .map { change in
                withExtendedLifetime(token) {
                    guard let change, change.version > version else {
                        return value
                    }

                    return change.value as? Value
                }
            }
            .eraseToAnyPublisher())
    }

    /// - Parameter includingCurrentValue: Whether the stream starts with the stored value, or `nil` if there's none: the
    ///   value this call reads, or a change published since. Reading it can throw, for example when the stored data can't be decoded.
    /// - Parameter bufferingPolicy: What the stream keeps of the values its consumer hasn't read yet. `.unbounded` keeps every
    ///   one, so a consumer slower than the changes falls behind and holds them all in memory; `.bufferingNewest(1)` keeps only
    ///   the latest, for a consumer that needs the current value rather than every change.
    open func stream<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>,
                                         includingCurrentValue: Bool = true,
                                         bufferingPolicy: AsyncStream<Value?>.Continuation.BufferingPolicy = .unbounded)
    async throws(Error) -> AsyncStream<Value?> {
        let publisher = try await publisher(forKey: key, includingCurrentValue: includingCurrentValue)
        return AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            let subscription = Subscription(publisher.sink {
                continuation.yield($0)
            })

            continuation.onTermination = { _ in
                subscription.cancel()
            }
        }
    }
}

// MARK: - Subscription

/// Keeps a stream's Combine subscription for its termination handler.
/// Cancelling a Combine subscription is thread-safe, but `AnyCancellable` isn't marked `Sendable`.
private final class Subscription: @unchecked Sendable {
    private let cancellable: AnyCancellable

    init(_ cancellable: AnyCancellable) {
        self.cancellable = cancellable
    }

    func cancel() {
        cancellable.cancel()
    }
}

// MARK: - ObservationToken

/// Lives as long as an observation's publisher, or any subscription to it, and releases the observation afterwards.
private final class ObservationToken: Sendable {
    private let onRelease: @Sendable () -> Void

    init(onRelease: @escaping @Sendable () -> Void) {
        self.onRelease = onRelease
    }

    deinit {
        onRelease()
    }
}

// MARK: - ObservationRegistry

/// Every observed key of the process, shared by all `ObservableStorage` instances.
final class ObservationRegistry: @unchecked Sendable {
    static let shared = ObservationRegistry()

    /// A storage type and one of its scopes: storages of different types never share observations.
    /// - Note: Unchecked only because `AnyHashable` hides that every scope is `Sendable`.
    struct ScopeID: Hashable, @unchecked Sendable {
        let storageType: ObjectIdentifier
        let scope: AnyHashable
    }

    private let lock = Lock()
    /// The observations of each scope, by key; the key includes the value type.
    private var observations = [ScopeID: [AnyHashable: Observation]]()

    /// The key's observation, made on first use; each call is one more reference.
    func register(_ key: AnyHashable, in scope: ScopeID) -> Observation {
        lock.withLock {
            let observation = observations[scope]?[key] ?? Observation()
            observation.references += 1
            observations[scope, default: [:]][key] = observation
            return observation
        }
    }

    /// Removes the observation once no publisher or subscription uses it, so it doesn't keep the last value in memory.
    func release(_ observation: Observation, forKey key: AnyHashable, in scope: ScopeID) {
        lock.withLock {
            observation.references -= 1
            guard observation.references == 0, observations[scope]?[key] === observation else {
                return
            }

            observations[scope]?[key] = nil
            if observations[scope]?.isEmpty == true {
                observations[scope] = nil
            }
        }
    }

    func observation(forKey key: AnyHashable, in scope: ScopeID) -> Observation? {
        lock.withLock { observations[scope]?[key] }
    }

    func observations(in scope: ScopeID) -> [Observation] {
        lock.withLock { Array((observations[scope] ?? [:]).values) }
    }
}

// MARK: - Observation

/// The published changes of one key; it holds no value read from the storage, which other writers can outdate.
/// - Note: Changes and their deliveries hold its own recursive lock, so subscribers never see two at once, and one that
///   saves the same key from its callback continues on the same thread.
final class Observation: @unchecked Sendable {
    /// The latest change, `nil` before the first.
    let subject = CurrentValueSubject<Change?, Never>(nil)
    /// Guarded by the registry's lock.
    var references = 0

    private let lock = NSRecursiveLock()
    private var latestVersion = 0

    /// The latest change's version: later changes have greater ones.
    var version: Int {
        lock.withLock { latestVersion }
    }

    func change(to value: Any?) {
        lock.withLock {
            latestVersion += 1
            subject.send(Change(value: value, version: latestVersion))
        }
    }

    // MARK: Change

    /// Saved, deleted or cleared through an observable storage.
    struct Change {
        let value: Any?
        let version: Int
    }
}
