//
//  UnifiedStorageUpdateTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class UnifiedStorageUpdateTests: XCTestCase {
    private typealias Key = UnifiedStorageKey<PlaceStorage, Int>

    private let error = MockError(id: 1)

    // MARK: Values

    func testTheTransformedValueIsSavedAndReturned() async throws {
        // Given
        let (place, key) = place()
        place.store(1, forKey: "key")
        let read = Read()

        // When
        let updated = try await UnifiedStorage().update(forKey: key) { value in
            read.value = value
            return (value ?? 0) + 1
        }

        // Then
        XCTAssertEqual(read.value, 1)
        XCTAssertEqual(updated, 2)
        XCTAssertEqual(place.value(forKey: "key"), 2)
        XCTAssertEqual(place.calls, [.fetch("key"), .save(Data("2".utf8), "key")])
    }

    func testWithoutAValueTheTransformGetsNil() async throws {
        // Given
        let (place, key) = place()
        let read = Read()
        read.value = 0

        // When
        let updated = try await UnifiedStorage().update(forKey: key) { value in
            read.value = value
            return 5
        }

        // Then
        XCTAssertNil(read.value)
        XCTAssertEqual(updated, 5)
        XCTAssertEqual(place.value(forKey: "key"), 5)
    }

    func testNilDeletesTheValue() async throws {
        // Given
        let (place, key) = place()
        place.store(1, forKey: "key")

        // When
        let updated = try await UnifiedStorage().update(forKey: key) { _ in nil }

        // Then
        XCTAssertNil(updated)
        XCTAssertNil(place.value(forKey: "key"))
        XCTAssertEqual(place.calls, [.fetch("key"), .delete("key")])
    }

    func testConcurrentUpdatesThroughOneStorageLoseNothing() async throws {
        // Given
        let (place, key) = place()
        let storage = UnifiedStorage()
        let updates = 200

        // When: increments from many tasks at once
        let increments = Task {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<updates {
                    group.addTask {
                        try await storage.update(forKey: key) { ($0 ?? 0) + 1 }
                    }
                }

                try await group.waitForAll()
            }
        }

        try await waitForValue(of: increments)

        // Then
        XCTAssertEqual(place.value(forKey: "key"), updates)
    }

    // MARK: Failures

    func testAFailedReadNeitherTransformsNorWrites() async throws {
        // Given
        let (place, key) = place()
        place.store(1, forKey: "key")
        place.fail(.fetch, with: error)
        let read = Read()

        // When - Then
        await assertThrows(CodingStorageError<PlaceStorage>.storage(error)) {
            try await UnifiedStorage().update(forKey: key) { value in
                read.called = true
                return value
            }
        }

        XCTAssertFalse(read.called)
        XCTAssertEqual(place.calls, [.fetch("key")])
    }

    func testAValueTheKeysTypeCantDecodeIsNeitherTransformedNorReplaced() async throws {
        // Given
        let (place, key) = place()
        place.storeData(Data("one".utf8), forKey: "key")
        let read = Read()

        // When - Then
        do {
            try await UnifiedStorage().update(forKey: key) { _ in
                read.called = true
                return 2
            }
            XCTFail("Expected an error")
        } catch {
            guard case .coding = error else {
                return XCTFail("Expected .coding, got \(error)")
            }
        }

        XCTAssertFalse(read.called)
        XCTAssertEqual(place.data(forKey: "key"), Data("one".utf8))
    }

    func testAFailedWriteKeepsTheValue() async throws {
        for (operation, result) in [(Place.Operation.save, Int?.some(2)), (.delete, nil)] {
            // Given
            let (place, key) = place()
            place.store(1, forKey: "key")
            place.fail(operation, with: error)

            // When - Then
            await assertThrows(CodingStorageError<PlaceStorage>.storage(error)) {
                try await UnifiedStorage().update(forKey: key) { _ in result }
            }

            XCTAssertEqual(place.value(forKey: "key"), 1, "\(operation)")
        }
    }

    func testAScopeWhoseStorageCantBeCreatedNeverTransforms() async throws {
        // Given
        let storage = UnifiedStorage(factory: UnavailableFactory())
        let read = Read()

        // When - Then
        await assertThrows(CodingStorageError<PlaceStorage>.storage(UnavailableFactory.error)) {
            try await storage.update(forKey: Key(key: "key", scope: MockScope(name: UnavailableFactory.scopeName))) { value in
                read.called = true
                return value
            }
        }

        XCTAssertFalse(read.called)
        let (place, key) = place()
        try await storage.save(1, forKey: key)
        XCTAssertEqual(place.value(forKey: "key"), 1, "the scope's hold was released")
    }

    // MARK: Waiting

    func testCallsInTheScopeWaitForAnUpdate() async throws {
        // Given: an update held at its write, with a read of the key after it
        let (place, key) = place()
        let storage = UnifiedStorage()
        place.store(1, forKey: "key")
        place.hold(.save)
        let update = Task { try await storage.update(forKey: key) { ($0 ?? 0) + 1 } }
        try await place.waitUntilHeld()
        let fetched = Task { try await storage.fetch(forKey: key) }
        try await waitUntil { storage.state(of: key.scope, in: PlaceStorage.self).waitingCalls == 1 }

        // When
        place.release()
        _ = try await waitForValue(of: update)

        // Then: the read waited, and saw the update's value
        let value = try await waitForValue(of: fetched)
        XCTAssertEqual(value, 2)
    }

    func testAnUpdateWaitsForCallsAlreadyRunningInTheScope() async throws {
        // Given: a save in the scope, held while it runs
        let (place, key) = place()
        let storage = UnifiedStorage()
        place.hold(.save)
        let save = Task { try await storage.save(10, forKey: key) }
        try await place.waitUntilHeld()
        let update = Task { try await storage.update(forKey: key) { ($0 ?? 0) + 1 } }
        try await waitUntil { storage.state(of: key.scope, in: PlaceStorage.self).waitingHolds == 1 }

        // Then: the update waits, and hasn't read yet
        XCTAssertEqual(place.calls, [])

        // When
        place.release()
        try await waitForValue(of: save)
        let updated = try await waitForValue(of: update)

        // Then: it updated the saved value
        XCTAssertEqual(updated, 11)
        XCTAssertEqual(place.value(forKey: "key"), 11)
    }

    func testCallsInOtherScopesDontWaitForAnUpdate() async throws {
        // Given: a held update
        let (place, key) = place()
        let (other, otherKey) = self.place()
        let storage = UnifiedStorage()
        place.hold(.save)
        let update = Task { try await storage.update(forKey: key) { _ in 1 } }
        try await place.waitUntilHeld()

        // When
        try await storage.save(3, forKey: otherKey)

        // Then
        XCTAssertEqual(other.value(forKey: "key"), 3)
        place.release()
        _ = try await waitForValue(of: update)
    }

    func testUpdatesAndMovesOfOneScopeTakeTurns() async throws {
        // Given: increments of the key's scope, and moves into it from another scope, all at once
        let (place, key) = place()
        let (source, _) = self.place()
        let storage = UnifiedStorage()
        source.store(100, forKey: "key")

        // When
        let turns = Task {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<50 {
                    group.addTask {
                        if index == 25 {
                            try await storage.move(key, from: source.scope)
                        } else {
                            try await storage.update(forKey: key) { ($0 ?? 0) + 1 }
                        }
                    }
                }

                try await group.waitForAll()
            }
        }

        try await waitForValue(of: turns)

        // Then: every increment counted, on the moved value if the move came first, or on their own if it came later and
        // kept the target's newer value
        let value = try XCTUnwrap(place.value(forKey: "key"))
        XCTAssertTrue([149, 49].contains(value), "\(value)")
        XCTAssertNil(source.value(forKey: "key"))
    }

    // MARK: Observation

    func testObserversSeeTheUpdatedValue() async throws {
        // Given
        let (_, key) = place()
        let storage = UnifiedStorage(observable: true)
        let values = PublishedValues()
        let subscription = try await storage.publisher(forKey: key, includingCurrentValue: false)?.sink { values.append($0) }

        // When
        try await storage.update(forKey: key) { _ in 1 }
        try await storage.update(forKey: key) { _ in nil }

        // Then
        XCTAssertEqual(values.all, [1, nil])
        subscription?.cancel()
    }

    // MARK: Helpers

    /// A scope of its own, and the key in it.
    private func place() -> (Place, Key) {
        let place = Place.named("update-\(UUID().uuidString)")
        return (place, Key(key: "key", scope: place.scope))
    }
}

// MARK: - Read

/// What a transform got, and whether it ran.
private final class Read: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int??
    private var ran = false

    var value: Int? {
        get { lock.withLock { stored ?? nil } }
        set { lock.withLock { stored = .some(newValue) } }
    }

    var called: Bool {
        get { lock.withLock { ran } }
        set { lock.withLock { ran = newValue } }
    }
}
