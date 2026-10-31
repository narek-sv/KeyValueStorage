//
//  ObservationRegistry.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.10.26.
//

import Combine
import Foundation

// MARK: - ObservationRegistry

/// Every observed key of the process, shared by all `ObservableKeyValueStorage` instances.
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

/// The observed state of one key.
/// - Note: Its state changes and deliveries hold its own recursive lock, so subscribers never see two at once, and one that
///   saves the same key from its callback continues on the same thread.
final class Observation: @unchecked Sendable {
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
