//
//  UnifiedStorageMoveTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class UnifiedStorageMoveTests: XCTestCase {
    private typealias Key = UnifiedStorageKey<PlaceStorage, Int>

    private let error = MockError(id: 1)

    // MARK: Values

    func testTheValueIsSavedInTheKeysScopeThenRemovedFromTheOther() async throws {
        let (source, target, key) = places()
        // Given
        source.store(1, forKey: "key")

        // When
        try await UnifiedStorage().move(key, from: source.scope)

        // Then
        XCTAssertNil(source.value(forKey: "key"))
        XCTAssertEqual(target.value(forKey: "key"), 1)
        XCTAssertEqual(source.calls, [.fetch("key"), .delete("key")])
        XCTAssertEqual(target.calls, [.fetch("key"), .save(Data("1".utf8), "key")])
    }

    func testMovingFromTheKeysOwnScopeChangesNothing() async throws {
        let (_, target, key) = places()
        // Given
        target.store(1, forKey: "key")

        // When
        try await UnifiedStorage().move(key, from: target.scope)

        // Then
        XCTAssertEqual(target.value(forKey: "key"), 1)
        XCTAssertEqual(target.calls, [])
    }

    func testWithoutAValueNothingChanges() async throws {
        let (source, target, key) = places()
        // Given
        target.store(2, forKey: "key")

        // When
        try await UnifiedStorage().move(key, from: source.scope)

        // Then
        XCTAssertEqual(target.value(forKey: "key"), 2)
        XCTAssertEqual(source.calls, [.fetch("key")])
        XCTAssertEqual(target.calls, [])
    }

    func testAValueAlreadyInTheKeysScopeIsKeptAndTheOtherRemoved() async throws {
        let (source, target, key) = places()
        // Given
        source.store(1, forKey: "key")
        target.store(2, forKey: "key")

        // When
        try await UnifiedStorage().move(key, from: source.scope)

        // Then
        XCTAssertNil(source.value(forKey: "key"))
        XCTAssertEqual(target.value(forKey: "key"), 2)
        XCTAssertEqual(target.calls, [.fetch("key")])
    }

    func testAValueTheKeysTypeCantDecodeChangesNothing() async throws {
        let (source, target, key) = places()
        // Given: the source holds the value as a string, which the key's value type can't decode
        source.storeData(Data("one".utf8), forKey: "key")

        // When - Then
        do {
            try await UnifiedStorage().move(key, from: source.scope)
            XCTFail("Expected an error")
        } catch {
            guard case .coding = error else {
                return XCTFail("Expected .coding, got \(error)")
            }
        }

        XCTAssertEqual(source.data(forKey: "key"), Data("one".utf8))
        XCTAssertEqual(target.calls, [])
    }

    // MARK: Failures

    func testAFailedReadOfEitherScopeChangesNothing() async throws {
        let (source, target, key) = places()
        for failing in [source, target] {
            // Given
            source.store(1, forKey: "key")
            failing.fail(.fetch, with: error)

            // When - Then
            await assertThrows(CodingStorageError<PlaceStorage>.storage(error)) { try await UnifiedStorage().move(key, from: source.scope) }
            XCTAssertEqual(source.value(forKey: "key"), 1)
            XCTAssertNil(target.value(forKey: "key"))
            failing.fail(.fetch, with: nil)
        }
    }

    func testAFailedSaveKeepsTheValueWhereItWas() async throws {
        let (source, target, key) = places()
        // Given
        source.store(1, forKey: "key")
        target.fail(.save, with: error)

        // When - Then
        await assertThrows(CodingStorageError<PlaceStorage>.storage(error)) { try await UnifiedStorage().move(key, from: source.scope) }
        XCTAssertEqual(source.value(forKey: "key"), 1)
        XCTAssertEqual(source.calls, [.fetch("key")])
    }

    func testAFailedRemovalIsFinishedByMovingAgain() async throws {
        let (source, target, key) = places()
        // Given: a move that saved the value but couldn't remove the old one
        let storage = UnifiedStorage()
        source.store(1, forKey: "key")
        source.fail(.delete, with: error)
        await assertThrows(CodingStorageError<PlaceStorage>.storage(error)) { try await storage.move(key, from: source.scope) }
        XCTAssertEqual(source.value(forKey: "key"), 1)
        XCTAssertEqual(target.value(forKey: "key"), 1)

        // When
        source.fail(.delete, with: nil)
        try await storage.move(key, from: source.scope)

        // Then: only the removal is done again
        XCTAssertNil(source.value(forKey: "key"))
        XCTAssertEqual(target.value(forKey: "key"), 1)
        XCTAssertEqual(target.calls, [.fetch("key"), .save(Data("1".utf8), "key"), .fetch("key")])
    }

    func testAScopeWhoseStorageCantBeCreatedChangesNothingAndReleasesTheOther() async throws {
        let (source, _, key) = places()
        // Given
        let storage = UnifiedStorage(factory: UnavailableFactory())
        let unavailable = MockScope(name: UnavailableFactory.scopeName)
        source.store(1, forKey: "key")

        // When - Then
        await assertThrows(CodingStorageError<PlaceStorage>.storage(UnavailableFactory.error)) { try await storage.move(key, from: unavailable) }
        await assertThrows(CodingStorageError<PlaceStorage>.storage(UnavailableFactory.error)) {
            try await storage.move(Key(key: "key", scope: unavailable), from: source.scope)
        }

        XCTAssertEqual(source.value(forKey: "key"), 1)
        XCTAssertEqual(source.calls, [], "both storages are created before the move reads or writes")
        let fetched = try await storage.fetch(forKey: Key(key: "key", scope: source.scope))
        XCTAssertEqual(fetched, 1, "the move's scopes are free again")
    }

    // MARK: Waiting

    func testCallsInEitherScopeWaitForAMove() async throws {
        let (source, _, key) = places()
        // Given: a move held at its last step, the removal, with calls in both scopes after it
        let storage = UnifiedStorage()
        source.store(1, forKey: "key")
        source.hold(.delete)
        let move = Task { try await storage.move(key, from: source.scope) }
        await source.waitUntilHeld()
        let fetchedSource = Task { try await storage.fetch(forKey: Key(key: "key", scope: source.scope)) }
        let fetchedTarget = Task { try await storage.fetch(forKey: key) }
        await settle()

        // When
        source.release()
        try await move.value

        // Then: neither saw the move half done, the value in both scopes
        let sourceValue = try await fetchedSource.value
        let targetValue = try await fetchedTarget.value
        XCTAssertNil(sourceValue)
        XCTAssertEqual(targetValue, 1)
    }

    func testAMoveWaitsForCallsAlreadyRunningInItsScopes() async throws {
        let (source, target, key) = places()
        // Given: a save in the key's scope, held while it runs
        let storage = UnifiedStorage()
        source.store(1, forKey: "key")
        target.hold(.save)
        let save = Task { try await storage.save(2, forKey: key) }
        await target.waitUntilHeld()
        let move = Task { try await storage.move(key, from: source.scope) }
        await settle()

        // Then: the move hasn't started
        XCTAssertEqual(source.calls, [])

        // When
        target.release()
        try await save.value
        try await move.value

        // Then: the move found the saved value newer than its own
        XCTAssertEqual(target.value(forKey: "key"), 2)
        XCTAssertNil(source.value(forKey: "key"))
    }

    func testCallsThatComeWhileAMoveWaitsRunAfterIt() async throws {
        let (source, target, key) = places()
        // Given: a move waiting for a running save, and a read of the source coming after the move
        let storage = UnifiedStorage()
        source.store(1, forKey: "key")
        target.hold(.save)
        let save = Task { try await storage.save(2, forKey: key) }
        await target.waitUntilHeld()
        let move = Task { try await storage.move(key, from: source.scope) }
        await settle()
        let fetched = Task { try await storage.fetch(forKey: Key(key: "key", scope: source.scope)) }
        await settle()

        // When
        target.release()
        try await save.value
        try await move.value

        // Then: the read waited for the move, which removed the source's value
        let value = try await fetched.value
        XCTAssertNil(value)
    }

    func testCallsWaitForEveryMoveOfTheirScope() async throws {
        let (source, target, key) = places()
        // Given: a move from the source to the target, held, then a move from the target to a third scope waiting for it,
        // and a read of the target coming after both
        let storage = UnifiedStorage()
        let third = Place.named("third-\(UUID().uuidString)")
        source.store(1, forKey: "key")
        source.hold(.delete)
        let first = Task { try await storage.move(key, from: source.scope) }
        await source.waitUntilHeld()
        let second = Task { try await storage.move(Key(key: "key", scope: third.scope), from: target.scope) }
        await settle()
        let fetched = Task { try await storage.fetch(forKey: key) }
        await settle()

        // When
        source.release()
        try await first.value
        try await second.value

        // Then: the read didn't run between the moves, when the target held the value
        let value = try await fetched.value
        XCTAssertNil(value)
        XCTAssertEqual(third.value(forKey: "key"), 1)
    }

    func testCallsInOtherScopesDontWaitForAMove() async throws {
        let (source, _, key) = places()
        // Given: a held move
        let storage = UnifiedStorage()
        let other = Place.named("other-\(UUID().uuidString)")
        source.store(1, forKey: "key")
        source.hold(.delete)
        let move = Task { try await storage.move(key, from: source.scope) }
        await source.waitUntilHeld()

        // When
        try await storage.save(3, forKey: Key(key: "key", scope: other.scope))
        let fetched = try await storage.fetch(forKey: Key(key: "key", scope: other.scope))

        // Then
        XCTAssertEqual(fetched, 3)
        source.release()
        try await move.value
    }

    func testCallsInOneScopeStillRunSideBySide() async throws {
        let (source, _, _) = places()
        // Given: a read in the scope, held while it runs
        let storage = UnifiedStorage()
        source.store(1, forKey: "key")
        source.hold(.fetch)
        let held = Task { try await storage.fetch(forKey: Key(key: "key", scope: source.scope)) }
        await source.waitUntilHeld()

        // When: more calls in the same scope
        let done = expectation(description: "calls beside the held one")
        let others = Task {
            try await storage.save(2, forKey: Key(key: "other", scope: source.scope))
            let fetched = try await storage.fetch(forKey: Key(key: "other", scope: source.scope))
            done.fulfill()
            return fetched
        }

        // Then: they finish while the held read still runs; on a timeout the test stops instead of waiting for them
        guard await XCTWaiter.fulfillment(of: [done], timeout: 5) == .completed else {
            return XCTFail("Calls in the scope waited for the held one")
        }

        source.release()
        let other = try await others.value
        let value = try await held.value
        XCTAssertEqual(other, 2)
        XCTAssertEqual(value, 1)
    }

    func testManyCallsAndMovesAtOnceNeverHangOrLoseAValue() async throws {
        for _ in 0..<20 {
            // Given: three scopes, a value in one of them
            let storage = UnifiedStorage()
            let scopes = (0..<3).map { _ in Place.named("busy-\(UUID().uuidString)") }
            scopes[0].store(1, forKey: "key")

            // When: moves between every pair, with reads and saves of the same key, all at once
            let finished = expectation(description: "every call and move finished")
            Task {
                // Not awaited by the test, so one that waits forever fails at the timeout instead of hanging
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for index in 0..<60 {
                        let from = scopes[index % 3].scope
                        let to = Key(key: "key", scope: scopes[(index + 1 + index / 3 % 2) % 3].scope)
                        group.addTask {
                            switch index % 4 {
                            case 0, 1:  try await storage.move(to, from: from)
                            case 2:     _ = try await storage.fetch(forKey: to)
                            default:    try await storage.save(index, forKey: Key(key: "key", scope: from))
                            }
                        }
                    }

                    try await group.waitForAll()
                }

                finished.fulfill()
            }

            // Then: nothing waits forever, and a value is left, since saves only add and moves never lose one
            guard await XCTWaiter.fulfillment(of: [finished], timeout: 10) == .completed else {
                return XCTFail("A call or move waited forever")
            }

            XCTAssertFalse(scopes.allSatisfy { $0.value(forKey: "key") == nil })
        }
    }

    func testOppositeMovesNeverDeadlockOrLoseTheValue() async throws {
        for _ in 0..<50 {
            // Given
            let storage = UnifiedStorage()
            let first = Place.named("first-\(UUID().uuidString)")
            let second = Place.named("second-\(UUID().uuidString)")
            first.store(1, forKey: "key")
            second.store(2, forKey: "key")

            // When
            async let toSecond: Void = storage.move(Key(key: "key", scope: second.scope), from: first.scope)
            async let toFirst: Void = storage.move(Key(key: "key", scope: first.scope), from: second.scope)
            _ = try await (toSecond, toFirst)

            // Then: one scope holds a value, whichever move came last
            XCTAssertEqual([first.value(forKey: "key"), second.value(forKey: "key")].compactMap { $0 }.count, 1)
        }
    }

    // MARK: Observation

    func testObserversOfBothKeysSeeTheMove() async throws {
        let (source, _, key) = places()
        // Given
        let storage = UnifiedStorage(observable: true)
        let sourceKey = Key(key: "key", scope: source.scope)
        let sourceValues = PublishedValues()
        let targetValues = PublishedValues()
        source.store(1, forKey: "key")
        let sourceSubscription = try await storage.publisher(forKey: sourceKey, includingCurrentValue: false)?.sink { sourceValues.append($0) }
        let targetSubscription = try await storage.publisher(forKey: key, includingCurrentValue: false)?.sink { targetValues.append($0) }

        // When
        try await storage.move(key, from: source.scope)

        // Then
        XCTAssertEqual(sourceValues.all, [nil])
        XCTAssertEqual(targetValues.all, [1])
        sourceSubscription?.cancel()
        targetSubscription?.cancel()
    }

    // MARK: Helpers

    /// A source and a target scope of their own, and the key in the target.
    private func places() -> (Place, Place, Key) {
        let id = UUID().uuidString
        let target = Place.named("target-\(id)")
        return (Place.named("source-\(id)"), target, Key(key: "key", scope: target.scope))
    }

    /// Lets tasks started just before reach the point where they wait.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 200_000_000)
    }
}
