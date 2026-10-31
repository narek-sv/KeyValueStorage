//
//  ObservableKeyValueStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.10.26.
//

import Combine

// MARK: - ObservableKeyValueStorage

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
open class ObservableKeyValueStorage<Storage: AsyncKeyValueDataStorage & Sendable>: @unchecked Sendable {
    public typealias Error = KeyValueCodingError<Storage>

    // MARK: Properties

    private let storage: AsyncKeyValueCodingStorage<Storage>
    private let registry = ObservationRegistry.shared

    public var scope: Storage.Scope {
        storage.scope
    }

    // MARK: Initializers

    public init(_ storage: AsyncKeyValueCodingStorage<Storage>) {
        self.storage = storage
    }

    // MARK: Main Functionality

    open func fetch<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws(Error) -> Value? {
        try await storage.fetch(forKey: key)
    }

    open func save<Value: CodingValue>(_ value: Value, forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws(Error) {
        try await storage.save(value, forKey: key)
        registry.observation(forKey: key, in: scopeID)?.change(to: value)
    }

    open func set<Value: CodingValue>(_ value: Value?, forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws(Error) {
        if let value {
            try await save(value, forKey: key)
        } else {
            try await delete(forKey: key)
        }
    }

    open func delete<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws(Error) {
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
    open func publisher<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>,
                                              includingCurrentValue: Bool = true) async throws(Error) -> KeyValuePublisher<Value?> {
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

        return KeyValuePublisher(states
            .compactMap { state in
                withExtendedLifetime(token) {
                    state.value(as: Value.self, includingSeeded: includingCurrentValue)
                }
            }
            .eraseToAnyPublisher())
    }

    /// - Parameter includingCurrentValue: Whether the stream starts with the currently stored value, or `nil` if there's none.
    ///   Reading it can throw, for example when the stored data can't be decoded.
    open func stream<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>,
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
