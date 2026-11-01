//
//  PlaceStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

import Foundation
@testable import KeyValueStorage

// MARK: - PlaceStorage

/// A storage of the `Place` named like its scope, so tests reach the storages `UnifiedStorage` creates.
struct PlaceStorage: AsyncDataStorage, Sendable {
    typealias Key = String
    typealias Error = MockError

    let scope: MockScope

    private var place: Place {
        Place.named(scope.name)
    }

    init(scope: MockScope) {
        self.scope = scope
    }

    func fetch(forKey key: String) async throws(MockError) -> Data? {
        try await place.perform(.fetch(key)) { $0[key] }
    }

    func save(_ value: Data, forKey key: String) async throws(MockError) {
        try await place.perform(.save(value, key)) { $0[key] = value }
    }

    func delete(forKey key: String) async throws(MockError) {
        try await place.perform(.delete(key)) { $0[key] = nil }
    }

    func clear() async throws(MockError) {
        try await place.perform(.clear) { $0 = [:] }
    }
}

// MARK: - Place

/// Values, recorded calls, failures, and an operation held until released, by name.
final class Place: @unchecked Sendable {
    enum Operation {
        case fetch, save, delete, clear
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var places = [String: Place]()

    let scope: MockScope
    private let lock = NSLock()
    private var values = [String: Data]()
    private var recorded = [DataStorageCall]()
    private var failures = [Operation: MockError]()
    private var held: Operation?
    private var heldCall: CheckedContinuation<Void, Never>?
    private var holdWaiter: CheckedContinuation<Void, Never>?

    private init(name: String) {
        self.scope = MockScope(name: name)
    }

    static func named(_ name: String) -> Place {
        lock.withLock {
            if let place = places[name] {
                return place
            }

            let place = Place(name: name)
            places[name] = place
            return place
        }
    }

    var calls: [DataStorageCall] {
        lock.withLock { recorded }
    }

    func store(_ value: Int, forKey key: String) {
        storeData(Data("\(value)".utf8), forKey: key)
    }

    func storeData(_ data: Data, forKey key: String) {
        lock.withLock { values[key] = data }
    }

    func value(forKey key: String) -> Int? {
        data(forKey: key).flatMap { Int(String(decoding: $0, as: UTF8.self)) }
    }

    func data(forKey key: String) -> Data? {
        lock.withLock { values[key] }
    }

    func fail(_ operation: Operation, with error: MockError?) {
        lock.withLock { failures[operation] = error }
    }

    /// Holds the next call of `operation` until `release()`.
    func hold(_ operation: Operation) {
        lock.withLock { held = operation }
    }

    /// Returns once a held call waits.
    func waitUntilHeld() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isHeld = lock.withLock {
                if heldCall == nil {
                    holdWaiter = continuation
                }

                return heldCall != nil
            }

            if isHeld {
                continuation.resume()
            }
        }
    }

    func release() {
        let call = lock.withLock {
            defer { heldCall = nil }
            return heldCall
        }

        call?.resume()
    }

    func perform<T>(_ call: DataStorageCall, _ body: (inout [String: Data]) -> T) async throws(MockError) -> T {
        let operation = Self.operation(of: call)
        let isHeld = lock.withLock {
            guard held == operation else {
                return false
            }

            held = nil
            return true
        }

        if isHeld {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let waiter = lock.withLock {
                    heldCall = continuation
                    defer { holdWaiter = nil }
                    return holdWaiter
                }

                waiter?.resume()
            }
        }

        return try lock.withLock { () -> Result<T, MockError> in
            recorded.append(call)
            if let error = failures[operation] {
                return .failure(error)
            }

            return .success(body(&values))
        }.get()
    }

    private static func operation(of call: DataStorageCall) -> Operation {
        switch call {
        case .fetch:    return .fetch
        case .save:     return .save
        case .delete:   return .delete
        case .clear:    return .clear
        }
    }
}

// MARK: - UnavailableFactory

/// Fails to create the storage of the scope named `scopeName`, and creates every other one.
struct UnavailableFactory: UnifiedStorageFactory {
    static let scopeName = "unavailable"
    static let error = MockError(id: 7)

    func dataStorage<Storage: UnifiedStorable>(for scope: Storage.Scope) async throws(Storage.Error) -> Storage {
        if (scope as? MockScope)?.name == Self.scopeName, let error = Self.error as? Storage.Error {
            throw error
        }

        return try await Storage(scope: scope)
    }
}

// MARK: - PublishedValues

/// Collects values delivered on any thread.
final class PublishedValues: @unchecked Sendable {
    private let lock = NSLock()
    private var values = [Int?]()

    var all: [Int?] {
        lock.withLock { values }
    }

    func append(_ value: Int?) {
        lock.withLock { values.append(value) }
    }
}
