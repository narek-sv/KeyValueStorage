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
/// - Two calls that save one key at once may deliver their values in the other order than they were written.
/// - Warning: Subclasses inherit `Sendable`: their own state must be thread-safe too.
open class ObservableStorage<Storage: AsyncDataStorage & Sendable>: @unchecked Sendable {
    public typealias Error = CodingStorageError<Storage>

    // MARK: Properties

    private let storage: AsyncCodingStorage<Storage>
    private let registry = ObservationRegistry.shared

    public var scope: Storage.Scope {
        storage.scope
    }

    // MARK: Initializers

    public init(_ storage: AsyncCodingStorage<Storage>) {
        self.storage = storage
    }

    // MARK: Main Functionality

    open func fetch<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>) async throws(Error) -> Value? {
        try await storage.fetch(forKey: key)
    }

    open func save<Value: CodingValue>(_ value: Value, forKey key: CodingStorageKey<Storage, Value>) async throws(Error) {
        try await storage.save(value, forKey: key)
        registry.observation(forKey: key, in: scopeID)?.change(to: value)
    }

    open func set<Value: CodingValue>(_ value: Value?, forKey key: CodingStorageKey<Storage, Value>) async throws(Error) {
        if let value {
            try await save(value, forKey: key)
        } else {
            try await delete(forKey: key)
        }
    }

    open func delete<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>) async throws(Error) {
        try await storage.delete(forKey: key)
        registry.observation(forKey: key, in: scopeID)?.change(to: nil)
    }

    /// Every observed key of the scope gets `nil`.
    open func clear() async throws(Error) {
        try await storage.clear()
        for observation in registry.observations(in: scopeID) {
            observation.change(to: nil)
        }
    }

    // MARK: Observation

    /// - Parameter includingCurrentValue: Whether the publisher first emits the currently stored value, or `nil` if there's none.
    ///   Reading it can throw, for example when the stored data can't be decoded.
    open func publisher<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>,
                                            includingCurrentValue: Bool = true) async throws(Error) -> ValuePublisher<Value?> {
        let scopeID = scopeID
        let observation = registry.register(key, in: scopeID)
        let token = ObservationToken { [registry] in
            registry.release(observation, forKey: key, in: scopeID)
        }

        // Registered before reading, so a value saved meanwhile wins over the one read here
        if includingCurrentValue, let version = observation.versionIfUnknown() {
            let value = try await fetch(forKey: key)
            observation.seed(value, ifUnchangedSince: version)
        }

        // The subject replays its state on subscription, so dropping it leaves only later changes
        let states = includingCurrentValue
            ? observation.subject.eraseToAnyPublisher()
            : observation.subject.dropFirst().eraseToAnyPublisher()

        return ValuePublisher(states
            .compactMap { state in
                withExtendedLifetime(token) {
                    state.value(as: Value.self, includingSeeded: includingCurrentValue)
                }
            }
            .eraseToAnyPublisher())
    }

    /// - Parameter includingCurrentValue: Whether the stream starts with the currently stored value, or `nil` if there's none.
    ///   Reading it can throw, for example when the stored data can't be decoded.
    open func stream<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>,
                                         includingCurrentValue: Bool = true) async throws(Error) -> AsyncStream<Value?> {
        let publisher = try await publisher(forKey: key, includingCurrentValue: includingCurrentValue)
        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let subscription = Subscription(publisher.sink {
                continuation.yield($0)
            })

            continuation.onTermination = { _ in
                subscription.cancel()
            }
        }
    }

    // MARK: Helpers

    private var scopeID: ObservationRegistry.ScopeID {
        .init(storageType: ObjectIdentifier(Storage.self), scope: AnyHashable(scope))
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
private final class ObservationRegistry: @unchecked Sendable {
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

/// The observed state of one key.
/// - Note: Its state changes and deliveries hold its own recursive lock, so subscribers never see two at once, and one that
///   saves the same key from its callback continues on the same thread.
private final class Observation: @unchecked Sendable {
    let subject = CurrentValueSubject<State, Never>(.unknown)
    /// Guarded by the registry's lock.
    var references = 0

    private let lock = NSRecursiveLock()
    private var version = 0

    func versionIfUnknown() -> Int? {
        lock.withLock { () -> Int? in
            if case .unknown = subject.value {
                return version
            }

            return nil
        }
    }

    func seed(_ value: Any?, ifUnchangedSince version: Int) {
        lock.withLock {
            guard self.version == version, case .unknown = subject.value else {
                return
            }

            subject.send(.seeded(value))
        }
    }

    func change(to value: Any?) {
        lock.withLock {
            version += 1
            subject.send(.changed(value))
        }
    }

    // MARK: State

    enum State {
        /// Nothing has been read or changed yet
        case unknown
        /// Read from the storage for a subscriber that wants the current value
        case seeded(Any?)
        /// Saved, deleted or cleared through an observable storage
        case changed(Any?)

        func value<Value>(as type: Value.Type, includingSeeded: Bool) -> Value?? {
            switch self {
            case .unknown:
                return nil
            case let .seeded(value):
                return includingSeeded ? .some(value as? Value) : nil
            case let .changed(value):
                return .some(value as? Value)
            }
        }
    }
}
