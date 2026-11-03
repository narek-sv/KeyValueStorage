//
//  UnifiedStorageCloseTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 02.11.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class UnifiedStorageCloseTests: XCTestCase {
    private typealias Entry = CountedStorage.Entry<Int>

    // MARK: Closing

    func testTheStorageIsReleasedAndTheNextCallCreatesANewOne() async throws {
        // Given: a scope whose storage a save created
        let (place, entry) = place()
        let storage = UnifiedStorage()
        try await run { try await storage.save(1, to: entry) }

        // When
        try await run { await storage.close(storage: CountedStorage.self, forScope: entry.scope) }

        // Then: the storage is gone by the time the close returns, and the next call creates a new one, which finds the value
        XCTAssertEqual(CountedStorage.alive(in: entry.scope), 0)
        let fetched = try await run { try await storage.fetch(entry) }
        XCTAssertEqual(fetched, 1)
        XCTAssertEqual(place.value(forKey: "key"), 1)
        XCTAssertEqual(CountedStorage.created(in: entry.scope), 2)
        XCTAssertEqual(CountedStorage.alive(in: entry.scope), 1)
    }

    func testClosingAScopeNeverUsedCreatesNothing() async throws {
        // Given
        let (_, entry) = place()
        let storage = UnifiedStorage()

        // When
        try await run { await storage.close(storage: CountedStorage.self, forScope: entry.scope) }

        // Then
        XCTAssertEqual(CountedStorage.created(in: entry.scope), 0)
    }

    func testOtherScopesKeepTheirStorages() async throws {
        // Given: two scopes with storages
        let (_, closedKey) = place()
        let (_, keptKey) = place()
        let storage = UnifiedStorage()
        try await run { try await storage.save(1, to: closedKey) }
        try await run { try await storage.save(2, to: keptKey) }

        // When
        try await run { await storage.close(storage: CountedStorage.self, forScope: closedKey.scope) }
        let kept = try await run { try await storage.fetch(keptKey) }

        // Then
        XCTAssertEqual(CountedStorage.alive(in: closedKey.scope), 0)
        XCTAssertEqual(kept, 2)
        XCTAssertEqual(CountedStorage.created(in: keptKey.scope), 1)
        XCTAssertEqual(CountedStorage.alive(in: keptKey.scope), 1)
    }

    // MARK: Waiting

    func testACloseWaitsForCallsAlreadyRunning() async throws {
        // Given: a save in the scope, held while it runs
        let (place, entry) = place()
        let storage = UnifiedStorage()
        place.hold(.save)
        let save = Task { try await storage.save(1, to: entry) }
        try await place.waitUntilHeld()

        // When
        let close = Task { await storage.close(storage: CountedStorage.self, forScope: entry.scope) }
        try await waitUntil { storage.scopes.state(of: entry.scope, in: CountedStorage.self).waitingHolds == 1 }

        // Then: the close waits, and the storage is still there
        XCTAssertEqual(CountedStorage.alive(in: entry.scope), 1)

        // When
        place.release()
        try await waitForValue(of: close)

        // Then: the close released the storage by the time it returned, after the save it waited for
        XCTAssertEqual(CountedStorage.alive(in: entry.scope), 0)
        try await waitForValue(of: save)
        XCTAssertEqual(place.value(forKey: "key"), 1)
    }

    func testCallsThatComeWhileACloseWaitsRunAfterItOnANewStorage() async throws {
        // Given: a close waiting for a running save, and a read coming after the close
        let (place, entry) = place()
        let storage = UnifiedStorage()
        place.hold(.save)
        let save = Task { try await storage.save(1, to: entry) }
        try await place.waitUntilHeld()
        let close = Task { await storage.close(storage: CountedStorage.self, forScope: entry.scope) }
        try await waitUntil { storage.scopes.state(of: entry.scope, in: CountedStorage.self).waitingHolds == 1 }
        let fetched = Task { try await storage.fetch(entry) }
        try await waitUntil { storage.scopes.state(of: entry.scope, in: CountedStorage.self).waitingCalls == 1 }

        // When
        place.release()
        try await waitForValue(of: save)
        try await waitForValue(of: close)

        // Then: the read waited for the close, and ran on a new storage
        let value = try await waitForValue(of: fetched)
        XCTAssertEqual(value, 1)
        XCTAssertEqual(CountedStorage.created(in: entry.scope), 2)
        XCTAssertEqual(CountedStorage.alive(in: entry.scope), 1)
    }

    func testAMoveQueuedBehindACloseRunsOnANewStorage() async throws {
        // Given: a close waiting for a running save, and a move into the scope queued behind it
        let (place, entry) = place()
        let source = Place.named("close-source-\(UUID().uuidString)")
        let storage = UnifiedStorage()
        source.store(7, forKey: "key")
        place.hold(.save)
        let save = Task { try await storage.save(1, to: entry) }
        try await place.waitUntilHeld()
        let close = Task { await storage.close(storage: CountedStorage.self, forScope: entry.scope) }
        try await waitUntil { storage.scopes.state(of: entry.scope, in: CountedStorage.self).waitingHolds == 1 }
        let move = Task { try await storage.move(entry, from: source.scope) }
        try await waitUntil { storage.scopes.state(of: entry.scope, in: CountedStorage.self).waitingHolds == 2 }

        // When
        place.release()
        try await waitForValue(of: save)
        try await waitForValue(of: close)
        try await waitForValue(of: move)

        // Then: the move ran after the close, on a new storage, and kept the saved value, as it's newer than its own
        XCTAssertEqual(CountedStorage.created(in: entry.scope), 2)
        XCTAssertEqual(place.value(forKey: "key"), 1)
        XCTAssertNil(source.value(forKey: "key"))
    }

    func testAScopeNeverHasTwoStoragesAtOnce() async throws {
        // Given
        let (_, entry) = place()
        let storage = UnifiedStorage()
        let rounds = 50

        // When: rounds of saves and a close of one scope, all at once, each round starting with a storage
        let work = Task {
            for round in 0..<rounds {
                try await storage.save(round, to: entry)
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for index in 0..<10 {
                        group.addTask {
                            if index == 5 {
                                await storage.close(storage: CountedStorage.self, forScope: entry.scope)
                            } else {
                                try await storage.save(index, to: entry)
                            }
                        }
                    }

                    try await group.waitForAll()
                }
            }
        }

        try await waitForValue(of: work)

        // Then: every close released its storage before calls came in again, and each round's close released one
        XCTAssertEqual(CountedStorage.mostAlive(in: entry.scope), 1)
        XCTAssertGreaterThanOrEqual(CountedStorage.created(in: entry.scope), rounds)
    }

    // MARK: Observation

    func testObserversKeepSeeingChangesAfterAClose() async throws {
        // Given: an observer of an entry whose scope is closed after it subscribed
        let (_, entry) = place()
        let storage = UnifiedStorage(observable: true)
        let values = PublishedValues()
        let publisher = try await run { try await storage.publisher(for: entry, includingCurrentValue: false) }
        let subscription = publisher?.sink { values.append($0) }
        try await run { await storage.close(storage: CountedStorage.self, forScope: entry.scope) }

        // When: a save through the new storage
        try await run { try await storage.save(1, to: entry) }

        // Then
        XCTAssertEqual(values.all, [1])
        subscription?.cancel()
    }

    // MARK: Helpers

    /// A scope of its own, the `Place` behind it, and the entry in it.
    private func place() -> (Place, Entry) {
        let place = Place.named("close-\(UUID().uuidString)")
        return (place, Entry(key: "key", scope: place.scope))
    }

    /// Runs `body` in a task of its own, and fails the test after `waitForValue`'s timeout instead of waiting forever.
    private func run<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await waitForValue(of: Task { try await body() })
    }
}

// MARK: - CountedStorage

/// A storage of the `Place` named like its scope, as `PlaceStorage` is, that counts its instances: how many were created,
/// and how many are still alive.
private final class CountedStorage: AsyncDataStorage, Sendable {
    typealias Key = String
    typealias Error = MockError

    private static let counts = Counts()

    let scope: MockScope
    private let place: PlaceStorage

    init(scope: MockScope) {
        self.scope = scope
        self.place = PlaceStorage(scope: scope)
        Self.counts.change(scope.name, created: 1, alive: 1)
    }

    deinit {
        Self.counts.change(scope.name, created: 0, alive: -1)
    }

    static func created(in scope: MockScope) -> Int {
        counts.get(scope.name).created
    }

    static func alive(in scope: MockScope) -> Int {
        counts.get(scope.name).alive
    }

    /// The most instances of the scope alive at once.
    static func mostAlive(in scope: MockScope) -> Int {
        counts.get(scope.name).mostAlive
    }

    func fetch(forKey key: String) async throws(MockError) -> Data? {
        try await place.fetch(forKey: key)
    }

    func save(_ value: Data, forKey key: String) async throws(MockError) {
        try await place.save(value, forKey: key)
    }

    func set(_ value: Data?, forKey key: String) async throws(MockError) {
        try await place.set(value, forKey: key)
    }

    func delete(forKey key: String) async throws(MockError) {
        try await place.delete(forKey: key)
    }

    func clear() async throws(MockError) {
        try await place.clear()
    }
}

// MARK: - Counts

/// The instances of each scope, counted from any thread.
private final class Counts: @unchecked Sendable {
    private let lock = NSLock()
    private var counts = [String: (created: Int, alive: Int, mostAlive: Int)]()

    func change(_ name: String, created: Int, alive: Int) {
        lock.withLock {
            let count = counts[name] ?? (0, 0, 0)
            counts[name] = (count.created + created, count.alive + alive, max(count.mostAlive, count.alive + alive))
        }
    }

    func get(_ name: String) -> (created: Int, alive: Int, mostAlive: Int) {
        lock.withLock { counts[name] ?? (0, 0, 0) }
    }
}
