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
    private typealias Entry = PlaceStorage.Entry<Int>

    private let error = MockError(id: 1)

    // MARK: Values

    func testTheValueIsSavedAtTheDestinationThenRemovedFromTheEntry() async throws {
        let (source, target, destination) = places()
        // Given
        source.store(1, forKey: "key")

        // When
        try await UnifiedStorage().move(source.entry, to: destination.scope)

        // Then
        XCTAssertNil(source.value(forKey: "key"))
        XCTAssertEqual(target.value(forKey: "key"), 1)
        XCTAssertEqual(source.calls, [.fetch("key"), .delete("key")])
        XCTAssertEqual(target.calls, [.fetch("key"), .save(Data("1".utf8), "key")])
    }

    func testAMoveOntoTheEntryItselfChangesNothing() async throws {
        let (_, target, destination) = places()
        // Given
        let storage = UnifiedStorage()
        target.store(1, forKey: "key")

        // When: to itself, its own scope and its own key
        try await storage.move(destination, to: destination)
        try await storage.move(destination, to: destination.scope)
        try await storage.move(destination, to: destination.key)

        // Then
        XCTAssertEqual(target.value(forKey: "key"), 1)
        XCTAssertEqual(target.calls, [])
    }

    func testAMoveToAKeyRenamesTheValueInItsScope() async throws {
        let (source, _, _) = places()
        // Given
        source.store(1, forKey: "old")

        // When
        try await UnifiedStorage().move(Entry(key: "old", scope: source.scope), to: "new")

        // Then
        XCTAssertNil(source.value(forKey: "old"))
        XCTAssertEqual(source.value(forKey: "new"), 1)
        XCTAssertEqual(source.calls, [.fetch("old"), .fetch("new"), .save(Data("1".utf8), "new"), .delete("old")])
    }

    func testARenameKeepsAValueAlreadyAtTheKey() async throws {
        let (source, _, _) = places()
        // Given
        source.store(1, forKey: "old")
        source.store(2, forKey: "new")

        // When
        try await UnifiedStorage().move(Entry(key: "old", scope: source.scope), to: "new")

        // Then: the value at the key is newer, as a move to a scope finds it
        XCTAssertNil(source.value(forKey: "old"))
        XCTAssertEqual(source.value(forKey: "new"), 2)
    }

    func testAMoveToAnEntryChangesItsKeyAndScopeAtOnce() async throws {
        let (source, target, _) = places()
        // Given
        source.store(1, forKey: "old")

        // When
        try await UnifiedStorage().move(Entry(key: "old", scope: source.scope), to: Entry(key: "new", scope: target.scope))

        // Then
        XCTAssertNil(source.value(forKey: "old"))
        XCTAssertNil(target.value(forKey: "old"))
        XCTAssertEqual(target.value(forKey: "new"), 1)
        XCTAssertEqual(source.calls, [.fetch("old"), .delete("old")])
        XCTAssertEqual(target.calls, [.fetch("new"), .save(Data("1".utf8), "new")])
    }

    func testAMoveToAKeyTakesAStringForAnExactStringKey() async throws {
        // Given: a key made at runtime, for a storage whose keys are `ExactString`
        let storage = UnifiedStorage()
        let scope = InMemoryStorage.Scope.own(namespace: .init("move-\(UUID().uuidString)"))
        let name = "renamed-\(42)"
        try await storage.save(1, to: InMemoryStorage.Entry<Int>(key: "key", scope: scope))

        // When
        try await storage.move(InMemoryStorage.Entry<Int>(key: "key", scope: scope), to: name)

        // Then
        let moved = try await storage.fetch(InMemoryStorage.Entry<Int>(key: "renamed-42", scope: scope))
        let left = try await storage.fetch(InMemoryStorage.Entry<Int>(key: "key", scope: scope))
        XCTAssertEqual(moved, 1)
        XCTAssertNil(left)
        try await storage.clear(storage: InMemoryStorage.self, forScope: scope)
    }

    func testWithoutAValueNothingChanges() async throws {
        let (source, target, destination) = places()
        // Given
        target.store(2, forKey: "key")

        // When
        try await UnifiedStorage().move(source.entry, to: destination.scope)

        // Then
        XCTAssertEqual(target.value(forKey: "key"), 2)
        XCTAssertEqual(source.calls, [.fetch("key")])
        XCTAssertEqual(target.calls, [])
    }

    func testAValueAlreadyAtTheDestinationIsKeptAndTheEntrysRemoved() async throws {
        let (source, target, destination) = places()
        // Given
        source.store(1, forKey: "key")
        target.store(2, forKey: "key")

        // When
        try await UnifiedStorage().move(source.entry, to: destination.scope)

        // Then
        XCTAssertNil(source.value(forKey: "key"))
        XCTAssertEqual(target.value(forKey: "key"), 2)
        XCTAssertEqual(target.calls, [.fetch("key")])
    }

    func testAValueTheEntrysTypeCantDecodeChangesNothing() async throws {
        let (source, target, destination) = places()
        // Given: the source holds the value as a string, which the destination's value type can't decode
        source.storeData(Data("one".utf8), forKey: "key")

        // When - Then
        do {
            try await UnifiedStorage().move(source.entry, to: destination.scope)
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
        let (source, target, destination) = places()
        for failing in [source, target] {
            // Given
            source.store(1, forKey: "key")
            failing.fail(.fetch, with: error)

            // When - Then
            await assertThrows(CodingStorageError<PlaceStorage>.storage(error)) { try await UnifiedStorage().move(source.entry, to: destination.scope) }
            XCTAssertEqual(source.value(forKey: "key"), 1)
            XCTAssertNil(target.value(forKey: "key"))
            failing.fail(.fetch, with: nil)
        }
    }

    func testAFailedSaveKeepsTheValueWhereItWas() async throws {
        let (source, target, destination) = places()
        // Given
        source.store(1, forKey: "key")
        target.fail(.save, with: error)

        // When - Then
        await assertThrows(CodingStorageError<PlaceStorage>.storage(error)) { try await UnifiedStorage().move(source.entry, to: destination.scope) }
        XCTAssertEqual(source.value(forKey: "key"), 1)
        XCTAssertEqual(source.calls, [.fetch("key")])
    }

    func testAFailedRemovalIsFinishedByMovingAgain() async throws {
        let (source, target, destination) = places()
        // Given: a move that saved the value but couldn't remove the old one
        let storage = UnifiedStorage()
        source.store(1, forKey: "key")
        source.fail(.delete, with: error)
        await assertThrows(CodingStorageError<PlaceStorage>.storage(error)) { try await storage.move(source.entry, to: destination.scope) }
        XCTAssertEqual(source.value(forKey: "key"), 1)
        XCTAssertEqual(target.value(forKey: "key"), 1)

        // When
        source.fail(.delete, with: nil)
        try await storage.move(source.entry, to: destination.scope)

        // Then: only the removal is done again
        XCTAssertNil(source.value(forKey: "key"))
        XCTAssertEqual(target.value(forKey: "key"), 1)
        XCTAssertEqual(target.calls, [.fetch("key"), .save(Data("1".utf8), "key"), .fetch("key")])
    }

    func testAScopeWhoseStorageCantBeCreatedChangesNothingAndReleasesTheOther() async throws {
        let (source, _, destination) = places()
        // Given
        let storage = UnifiedStorage(factory: UnavailableFactory())
        let unavailable = MockScope(name: UnavailableFactory.scopeName)
        source.store(1, forKey: "key")

        // When - Then
        await assertThrows(CodingStorageError<PlaceStorage>.storage(UnavailableFactory.error)) { try await storage.move(Entry(key: "key", scope: unavailable), to: destination.scope) }
        await assertThrows(CodingStorageError<PlaceStorage>.storage(UnavailableFactory.error)) {
            try await storage.move(source.entry, to: unavailable)
        }

        XCTAssertEqual(source.value(forKey: "key"), 1)
        XCTAssertEqual(source.calls, [], "both storages are created before the move reads or writes")
        let fetched = try await waitForValue(of: Task { try await storage.fetch(Entry(key: "key", scope: source.scope)) })
        XCTAssertEqual(fetched, 1, "the move's scopes are free again")
    }

    // MARK: Waiting

    func testCallsInEitherScopeWaitForAMove() async throws {
        let (source, _, destination) = places()
        // Given: a move held at its last step, the removal, with calls in both scopes after it
        let storage = UnifiedStorage()
        source.store(1, forKey: "key")
        source.hold(.delete)
        let move = Task { try await storage.move(source.entry, to: destination.scope) }
        try await source.waitUntilHeld()
        let fetchedSource = Task { try await storage.fetch(Entry(key: "key", scope: source.scope)) }
        let fetchedTarget = Task { try await storage.fetch(destination) }
        try await waitUntil {
            storage.scopes.state(of: source.scope, in: PlaceStorage.self).waitingCalls == 1
                && storage.scopes.state(of: destination.scope, in: PlaceStorage.self).waitingCalls == 1
        }

        // When
        source.release()
        try await waitForValue(of: move)

        // Then: neither saw the move half done, the value in both scopes
        let sourceValue = try await waitForValue(of: fetchedSource)
        let targetValue = try await waitForValue(of: fetchedTarget)
        XCTAssertNil(sourceValue)
        XCTAssertEqual(targetValue, 1)
    }

    func testAMoveWaitsForCallsAlreadyRunningInItsScopes() async throws {
        let (source, target, destination) = places()
        // Given: a save in the destination's scope, held while it runs
        let storage = UnifiedStorage()
        source.store(1, forKey: "key")
        target.hold(.save)
        let save = Task { try await storage.save(2, to: destination) }
        try await target.waitUntilHeld()
        let move = Task { try await storage.move(source.entry, to: destination.scope) }
        try await waitUntil { storage.scopes.state(of: source.scope, in: PlaceStorage.self).waitingHolds == 1 }

        // Then: the move waits, and hasn't started
        XCTAssertEqual(source.calls, [])

        // When
        target.release()
        try await waitForValue(of: save)
        try await waitForValue(of: move)

        // Then: the move found the saved value newer than its own
        XCTAssertEqual(target.value(forKey: "key"), 2)
        XCTAssertNil(source.value(forKey: "key"))
    }

    func testCallsThatComeWhileAMoveWaitsRunAfterIt() async throws {
        let (source, target, destination) = places()
        // Given: a move waiting for a running save, and a read of the source coming after the move
        let storage = UnifiedStorage()
        source.store(1, forKey: "key")
        target.hold(.save)
        let save = Task { try await storage.save(2, to: destination) }
        try await target.waitUntilHeld()
        let move = Task { try await storage.move(source.entry, to: destination.scope) }
        try await waitUntil { storage.scopes.state(of: source.scope, in: PlaceStorage.self).waitingHolds == 1 }
        let fetched = Task { try await storage.fetch(Entry(key: "key", scope: source.scope)) }
        try await waitUntil { storage.scopes.state(of: source.scope, in: PlaceStorage.self).waitingCalls == 1 }

        // When
        target.release()
        try await waitForValue(of: save)
        try await waitForValue(of: move)

        // Then: the read waited for the move, which removed the source's value
        let value = try await waitForValue(of: fetched)
        XCTAssertNil(value)
    }

    func testCallsWaitForEveryMoveOfTheirScope() async throws {
        let (source, target, destination) = places()
        // Given: a move from the source to the target, held, then a move from the target to a third scope waiting for it,
        // and a read of the target coming after both
        let storage = UnifiedStorage()
        let third = Place.named("third-\(UUID().uuidString)")
        source.store(1, forKey: "key")
        source.hold(.delete)
        let first = Task { try await storage.move(source.entry, to: destination.scope) }
        try await source.waitUntilHeld()
        let second = Task { try await storage.move(destination, to: third.scope) }
        try await waitUntil { storage.scopes.state(of: target.scope, in: PlaceStorage.self).waitingHolds == 1 }
        let fetched = Task { try await storage.fetch(destination) }
        try await waitUntil { storage.scopes.state(of: target.scope, in: PlaceStorage.self).waitingCalls == 1 }

        // When
        source.release()
        try await waitForValue(of: first)
        try await waitForValue(of: second)

        // Then: the read didn't run between the moves, when the target held the value
        let value = try await waitForValue(of: fetched)
        XCTAssertNil(value)
        XCTAssertEqual(third.value(forKey: "key"), 1)
    }

    func testAMoveWaitsForCallsLetInAfterAnotherMove() async throws {
        let (source, target, destination) = places()
        // Given: a read of the target that waited for a move, was let in after it, and is held while it runs
        let storage = UnifiedStorage()
        let other = Place.named("other-\(UUID().uuidString)")
        source.store(1, forKey: "key")
        other.store(3, forKey: "key")
        source.hold(.delete)
        let first = Task { try await storage.move(source.entry, to: destination.scope) }
        try await source.waitUntilHeld()
        let fetched = Task { try await storage.fetch(destination) }
        try await waitUntil { storage.scopes.state(of: destination.scope, in: PlaceStorage.self).waitingCalls == 1 }
        target.hold(.fetch)
        source.release()
        try await waitForValue(of: first)
        try await target.waitUntilHeld()

        // When: a move from a third scope into the target
        let second = Task { try await storage.move(other.entry, to: destination.scope) }

        // Then: it waits for the read, which still runs
        try await waitUntil { storage.scopes.state(of: destination.scope, in: PlaceStorage.self).waitingHolds == 1 }
        XCTAssertEqual(other.calls, [])

        // When
        target.release()

        // Then: the read saw the first move's value, and the second move kept it, as it's newer than its own
        let value = try await waitForValue(of: fetched)
        try await waitForValue(of: second)
        XCTAssertEqual(value, 1)
        XCTAssertEqual(target.value(forKey: "key"), 1)
        XCTAssertNil(other.value(forKey: "key"))
    }

    func testCallsInOtherScopesDontWaitForAMove() async throws {
        let (source, _, destination) = places()
        // Given: a held move
        let storage = UnifiedStorage()
        let other = Place.named("other-\(UUID().uuidString)")
        source.store(1, forKey: "key")
        source.hold(.delete)
        let move = Task { try await storage.move(source.entry, to: destination.scope) }
        try await source.waitUntilHeld()

        // When
        try await storage.save(3, to: Entry(key: "key", scope: other.scope))
        let fetched = try await storage.fetch(Entry(key: "key", scope: other.scope))

        // Then
        XCTAssertEqual(fetched, 3)
        source.release()
        try await waitForValue(of: move)
    }

    func testCallsInOneScopeStillRunSideBySide() async throws {
        let (source, _, _) = places()
        // Given: a read in the scope, held while it runs
        let storage = UnifiedStorage()
        source.store(1, forKey: "key")
        source.hold(.fetch)
        let held = Task { try await storage.fetch(Entry(key: "key", scope: source.scope)) }
        try await source.waitUntilHeld()

        // When: more calls in the same scope
        let done = expectation(description: "calls beside the held one")
        let others = Task {
            try await storage.save(2, to: Entry(key: "other", scope: source.scope))
            let fetched = try await storage.fetch(Entry(key: "other", scope: source.scope))
            done.fulfill()
            return fetched
        }

        // Then: they finish while the held read still runs; on a timeout the test stops instead of waiting for them
        guard await XCTWaiter.fulfillment(of: [done], timeout: 5) == .completed else {
            return XCTFail("Calls in the scope waited for the held one")
        }

        source.release()
        let other = try await waitForValue(of: others)
        let value = try await waitForValue(of: held)
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
                        let entry = scopes[index % 3].entry
                        let destination = scopes[(index + 1 + index / 3 % 2) % 3].entry
                        group.addTask {
                            switch index % 4 {
                            case 0, 1:  try await storage.move(entry, to: destination)
                            case 2:     _ = try await storage.fetch(destination)
                            default:    try await storage.save(index, to: entry)
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

            // When: both at once, not awaited by the test, so a deadlock fails at the timeout instead of hanging
            let finished = expectation(description: "both moves finished")
            Task {
                do {
                    async let toSecond: Void = storage.move(first.entry, to: second.scope)
                    async let toFirst: Void = storage.move(second.entry, to: first.scope)
                    _ = try await (toSecond, toFirst)
                } catch {
                    XCTFail("A move failed: \(error)")
                }

                finished.fulfill()
            }

            guard await XCTWaiter.fulfillment(of: [finished], timeout: 5) == .completed else {
                return XCTFail("The moves deadlocked")
            }

            // Then: one scope holds a value, whichever move came last
            XCTAssertEqual([first.value(forKey: "key"), second.value(forKey: "key")].compactMap { $0 }.count, 1)
        }
    }

    // MARK: Observation

    func testObserversOfBothEntriesSeeTheMove() async throws {
        let (source, _, destination) = places()
        // Given
        let storage = UnifiedStorage(observable: true)
        let sourceValues = PublishedValues()
        let targetValues = PublishedValues()
        source.store(1, forKey: "key")
        let sourceSubscription = try await storage.publisher(for: source.entry, includingCurrentValue: false)?.sink { sourceValues.append($0) }
        let targetSubscription = try await storage.publisher(for: destination, includingCurrentValue: false)?.sink { targetValues.append($0) }

        // When
        try await storage.move(source.entry, to: destination.scope)

        // Then
        XCTAssertEqual(sourceValues.all, [nil])
        XCTAssertEqual(targetValues.all, [1])
        sourceSubscription?.cancel()
        targetSubscription?.cancel()
    }

    // MARK: Helpers

    /// A source and a target scope of their own, and the destination: the entry in the target.
    private func places() -> (Place, Place, Entry) {
        let id = UUID().uuidString
        let target = Place.named("target-\(id)")
        return (Place.named("source-\(id)"), target, target.entry)
    }
}

// MARK: - Place + Entry

private extension Place {
    /// The entry of the key the tests move, in this place's scope.
    var entry: PlaceStorage.Entry<Int> {
        .init(key: "key", scope: scope)
    }
}
