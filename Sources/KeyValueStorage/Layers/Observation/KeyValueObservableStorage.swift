//
//  KeyValueObservableStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 30.12.23.
//

import Combine

// MARK: - KeyValueObservations

@CodingStorageActor
private final class KeyValueObservations {
    fileprivate static var observations = [AnyHashable?: [AnyHashable: Any]]()
}

// MARK: - KeyValueObservableStorage

/// A coding storage that publishes the changes made through it.
///
/// - Changes are delivered serially on `CodingStorageActor`, not on the main thread.
///   Use `receive(on: DispatchQueue.main)`, or hop to the main actor, before updating UI.
///   Streams resume on the executor of the task that iterates them.
/// - Only changes made through observable storages in this process are published, from any instance.
///   Changes from other processes (such as app extensions), from storages created without observation,
///   or written directly to `UserDefaults`, the keychain or files aren't.
/// - Note: Its storage is `Sendable`, because observation reaches it from `CodingStorageActor`; wrap a synchronous one in `IsolatedKeyValueDataStorage`.
open class KeyValueObservableStorage<Storage: AsyncKeyValueDataStorage & Sendable>: AsyncKeyValueCodingStorage<Storage>, @unchecked Sendable {
        
    // MARK: Observation

    /// - Parameter includingCurrentValue: Whether the stream starts with the currently stored value, or `nil` if there's none.
    ///   Reading it can throw, for example when the stored data can't be decoded.
    public func stream<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>,
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
    
    /// - Parameter includingCurrentValue: Whether the publisher first emits the currently stored value, or `nil` if there's none.
    ///   Reading it can throw, for example when the stored data can't be decoded.
    public func publisher<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>,
                                              includingCurrentValue: Bool = true) async throws(Error) -> KeyValuePublisher<Value?> {
        let observation = await register(forKey: key)
        let token = ObservationToken { [self] in
            Task { @CodingStorageActor in
                self.release(observation, forKey: key)
            }
        }
        
        // The observation is registered before reading, so a value saved meanwhile wins over the one read here
        if includingCurrentValue, let version = await observation.versionIfUnknown() {
            let value = try await fetch(forKey: key)
            await observation.seed(value, ifUnchangedSince: version)
        }
        
        return await makePublisher(for: observation, token: token, includingCurrentValue: includingCurrentValue)
    }
    
    // MARK: Main Functionality
    
    public override func save<Value: CodingValue>(_ value: Value, forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws(Error) {
        try await super.save(value, forKey: key)
        await send(value, forKey: key)
    }
    
    public override func delete<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws(Error) {
        try await super.delete(forKey: key)
        await send(nil, forKey: key)
    }
    
    public override func clear() async throws(Error) {
        try await super.clear()
        await sendNilToAll()
    }
    
    // MARK: Helpers
    
    @CodingStorageActor
    private func makePublisher<Value: CodingValue>(for observation: Observation,
                                                   token: ObservationToken,
                                                   includingCurrentValue: Bool) -> KeyValuePublisher<Value?> {
        // The subject replays its state on subscription, so dropping it leaves only later changes
        let states = includingCurrentValue
            ? observation.subject.eraseToAnyPublisher()
            : observation.subject.dropFirst().eraseToAnyPublisher()
        
        // Combine runs the closure on the subscriber's thread when replaying, so it mustn't be isolated to the actor
        return KeyValuePublisher(states
            .compactMap { @Sendable state in
                withExtendedLifetime(token) {
                    state.value(as: Value.self, includingSeeded: includingCurrentValue)
                }
            }
            .eraseToAnyPublisher())
    }
    
    @CodingStorageActor
    private func register<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) -> Observation {
        if let observation = KeyValueObservations.observations[scope]?[key] as? Observation {
            observation.references += 1
            return observation
        }
        
        let observation = Observation()
        observation.references = 1
        KeyValueObservations.observations[scope, default: [:]][key] = observation
        return observation
    }
    
    /// Removes the observation once no publisher or subscription uses it, so it doesn't keep the last value in memory.
    @CodingStorageActor
    private func release<Value: CodingValue>(_ observation: Observation, forKey key: KeyValueCodingStorageKey<Storage, Value>) {
        observation.references -= 1
        guard observation.references == 0, KeyValueObservations.observations[scope]?[key] as? Observation === observation else {
            return
        }
        
        KeyValueObservations.observations[scope]?[key] = nil
        if KeyValueObservations.observations[scope]?.isEmpty == true {
            KeyValueObservations.observations[scope] = nil
        }
    }
    
    @CodingStorageActor
    private func send<Value: CodingValue>(_ value: Value?, forKey key: KeyValueCodingStorageKey<Storage, Value>) {
        (KeyValueObservations.observations[scope]?[key] as? Observation)?.change(to: value)
    }
    
    @CodingStorageActor
    private func sendNilToAll() {
        for observation in (KeyValueObservations.observations[scope] ?? [:]).values {
            (observation as? Observation)?.change(to: nil)
        }
    }
    
    // MARK: Nested Types
    
    /// The observed state of one key. Nested in the generic class, so storages of different types never share it.
    @CodingStorageActor
    private final class Observation {
        let subject = CurrentValueSubject<State, Never>(.unknown)
        var references = 0
        private var version = 0
        
        func versionIfUnknown() -> Int? {
            if case .unknown = subject.value {
                return version
            }
            
            return nil
        }
        
        func seed<Value: Sendable>(_ value: Value?, ifUnchangedSince version: Int) {
            guard self.version == version, case .unknown = subject.value else {
                return
            }
            
            subject.send(.seeded(value))
        }
        
        func change(to value: Any?) {
            version += 1
            subject.send(.changed(value))
        }
    }
    
    private enum State {
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
