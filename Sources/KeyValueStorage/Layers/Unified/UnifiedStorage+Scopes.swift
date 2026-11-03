//
//  UnifiedStorage+Scopes.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 03.11.26.
//

// MARK: - UnifiedStorage + Scopes

extension UnifiedStorage {
    /// Each storage type and scope's storage, created on first use through the factory, and the calls, moves, updates and
    /// closes in it: one lock guards both, so a call is let in and gets its storage in one lookup.
    final class Scopes: @unchecked Sendable {

        // MARK: Properties

        private let factory: any UnifiedStorageFactory
        /// Guards the slots and the waiting holds; held only to look up or change them, never across an `await`.
        private let lock = Lock()
        /// Each storage type's `SlotTable`, made on first use and kept: typed tables hash scopes without boxing them.
        private var tables = [ObjectIdentifier: AnyObject]()
        /// Moves, updates and closes waiting to hold their scopes, in the order they came.
        private var waitingHolds = [WaitingHold]()

        // MARK: Initializers

        init(factory: any UnifiedStorageFactory) {
            self.factory = factory
        }

        // MARK: Calls and Holds

        /// Runs `body` with the scope's storage, once no move, update or close holds or waits for the scope.
        func withScope<Storage: UnifiedStorable, T>(
            _ scope: Storage.Scope,
            _ body: (ScopeStorage<Storage>) async throws(CodingStorageError<Storage>) -> T
        ) async throws(CodingStorageError<Storage>) -> T {
            let (slot, creation) = await enterCall(scope, of: Storage.self)
            defer {
                leaveCall(slot)
            }

            // Consumed, so the call lets go of the storage before it leaves the scope: a close let in next releases it at once
            return try await body(storage(in: slot, from: consume creation))
        }

        /// Runs `body` with the scopes' storages, all created first, once no call runs in any of them; calls in them wait meanwhile.
        func withHeldScopes<Storage: UnifiedStorable, T>(
            _ scopes: [Storage.Scope],
            _ body: ([ScopeStorage<Storage>]) async throws(CodingStorageError<Storage>) -> T
        ) async throws(CodingStorageError<Storage>) -> T {
            let slots = lock.withLock {
                scopes.map { slot(for: $0, of: Storage.self) }
            }

            await enterHold(slots)
            defer {
                leaveHold(slots)
            }

            var storages = [ScopeStorage<Storage>]()
            for (slot, scope) in zip(slots, scopes) {
                let creation = lock.withLock { self.creation(in: slot, for: scope) }
                storages.append(try await storage(in: slot, from: creation))
            }

            return try await body(storages)
        }

        /// Lets go of the scope's storage once no call runs in it, so the next call creates a new one; calls wait meanwhile.
        func close<Storage: UnifiedStorable>(_ scope: Storage.Scope, of _: Storage.Type) async {
            let slot = lock.withLock { self.slot(for: scope, of: Storage.self) }
            await enterHold([slot])

            // Released here, outside the lock and before calls come in again: closing a database can take a while
            _ = lock.withLock { () -> CreationTask<Storage>? in
                defer {
                    slot.creation = nil
                }

                return slot.creation
            }

            leaveHold([slot])
        }

        /// What the scope's calls, moves, updates and closes are doing, for tests, which wait for a state instead of sleeping.
        func state<Storage: UnifiedStorable>(of scope: Storage.Scope, in _: Storage.Type) -> ScopeState {
            lock.withLock {
                let slot = self.slot(for: scope, of: Storage.self)
                return ScopeState(runningCalls: slot.calls, waitingCalls: slot.waitingCalls.count,
                                  isHeld: slot.isHeld, waitingHolds: slot.waitingHolds)
            }
        }

        // MARK: Slots

        /// Under the lock: the scope's slot, made on first use, in its storage type's table.
        private func slot<Storage: UnifiedStorable>(for scope: Storage.Scope, of _: Storage.Type) -> StorageSlot<Storage> {
            let table: SlotTable<Storage>
            if let found = tables[ObjectIdentifier(Storage.self)] {
                // Unchecked: each storage type's table is filed under its own identifier
                table = unsafeDowncast(found, to: SlotTable<Storage>.self)
            } else {
                table = SlotTable()
                tables[ObjectIdentifier(Storage.self)] = table
            }

            if let slot = table.slots[scope] {
                return slot
            }

            let slot = StorageSlot<Storage>()
            table.slots[scope] = slot
            return slot
        }

        /// Lets the call into the scope, and gives it the storage's creation from the same lookup.
        private func enterCall<Storage: UnifiedStorable>(
            _ scope: Storage.Scope,
            of _: Storage.Type
        ) async -> (StorageSlot<Storage>, CreationTask<Storage>) {
            let (slot, creation) = lock.withLock { () -> (StorageSlot<Storage>, CreationTask<Storage>?) in
                let found = self.slot(for: scope, of: Storage.self)
                guard found.admitsCalls else {
                    return (found, nil)
                }

                found.calls += 1
                return (found, self.creation(in: found, for: scope))
            }

            if let creation {
                return (slot, creation)
            }

            // Admitted at once if the scope was freed since the check above, so a hold that ends meanwhile can't miss this call
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let calls = lock.withLock {
                    slot.waitingCalls.append(continuation)
                    return admitCalls(in: slot)
                }

                resume(calls)
            }

            return (slot, lock.withLock { self.creation(in: slot, for: scope) })
        }

        private func leaveCall(_ slot: Slot) {
            let holds = lock.withLock {
                slot.calls -= 1
                return admitHolds()
            }

            resume(holds)
        }

        private func enterHold(_ slots: [Slot]) async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let holds = lock.withLock {
                    slots.forEach { $0.waitingHolds += 1 }
                    waitingHolds.append(WaitingHold(slots: slots, continuation: continuation))
                    return admitHolds()
                }

                resume(holds)
            }
        }

        private func leaveHold(_ slots: [Slot]) {
            let (calls, holds) = lock.withLock {
                var calls = [CheckedContinuation<Void, Never>]()
                for slot in slots {
                    slot.isHeld = false
                    calls += admitCalls(in: slot)
                }

                return (calls, admitHolds())
            }

            resume(calls + holds)
        }

        /// After unlocking: resumes the calls and holds let in under the lock.
        private func resume(_ continuations: [CheckedContinuation<Void, Never>]) {
            continuations.forEach { $0.resume() }
        }

        /// Under the lock: lets in the slot's waiting calls once no move, update or close holds or waits for it; returns them to resume after unlocking.
        private func admitCalls(in slot: Slot) -> [CheckedContinuation<Void, Never>] {
            guard slot.admitsCalls else {
                return []
            }

            let calls = slot.waitingCalls
            slot.calls += calls.count
            slot.waitingCalls = []
            return calls
        }

        /// Under the lock: lets in every waiting hold whose scopes are free, oldest first; returns them to resume after unlocking.
        private func admitHolds() -> [CheckedContinuation<Void, Never>] {
            var admitted = [CheckedContinuation<Void, Never>]()
            waitingHolds.removeAll { hold in
                guard hold.slots.allSatisfy(\.admitsHold) else {
                    return false
                }

                for slot in hold.slots {
                    slot.isHeld = true
                    slot.waitingHolds -= 1
                }

                admitted.append(hold.continuation)
                return true
            }

            return admitted
        }

        // MARK: Storages

        /// Under the lock: the slot's storage creation, started on first use; concurrent first calls share it.
        private func creation<Storage: UnifiedStorable>(in slot: StorageSlot<Storage>, for scope: Storage.Scope) -> CreationTask<Storage> {
            if let creation = slot.creation {
                return creation
            }

            let factory = factory
            let creation = CreationTask<Storage> {
                do throws(Storage.Error) {
                    let dataStorage: Storage = try await factory.dataStorage(for: scope)
                    let coding = await factory.codingStorage(for: dataStorage)
                    return .success(ScopeStorage(coding: coding, observable: await factory.observableStorage(for: coding)))
                } catch {
                    return .failure(error)
                }
            }

            slot.creation = creation
            return creation
        }

        /// The created storage; a failure isn't kept, so a later call can retry.
        private func storage<Storage: UnifiedStorable>(
            in slot: StorageSlot<Storage>,
            from creation: CreationTask<Storage>
        ) async throws(CodingStorageError<Storage>) -> ScopeStorage<Storage> {
            switch await creation.value {
            case let .success(storage):
                return storage
            case let .failure(error):
                lock.withLock {
                    if slot.creation == creation {
                        slot.creation = nil
                    }
                }

                throw .storage(error)
            }
        }

        /// Creation can't fail with a typed error inside a `Task`, so the task returns its outcome instead.
        private typealias CreationTask<Storage: UnifiedStorable> = Task<Result<ScopeStorage<Storage>, Storage.Error>, Never>
    }
}

// MARK: - UnifiedStorage.Scopes + Slot

extension UnifiedStorage.Scopes {
    /// A storage type and scope: the calls, moves, updates and closes that use it. Guarded by the lock.
    private class Slot: @unchecked Sendable {
        /// Calls running in the scope.
        var calls = 0
        /// Whether a move, an update or a close holds the scope.
        var isHeld = false
        /// Moves, updates and closes waiting to hold the scope; new calls wait behind them, so they never wait forever.
        var waitingHolds = 0
        /// Calls waiting for the scope's holds to end.
        var waitingCalls = [CheckedContinuation<Void, Never>]()

        var admitsCalls: Bool {
            !isHeld && waitingHolds == 0
        }

        var admitsHold: Bool {
            !isHeld && calls == 0
        }
    }

    /// A `Slot` with its storage type's creation, so finding it needs no cast.
    private final class StorageSlot<Storage: UnifiedStorable>: Slot, @unchecked Sendable {
        /// `nil` before the first call, and after a failed creation.
        var creation: CreationTask<Storage>?
    }

    /// A storage type's slots, by scope.
    private final class SlotTable<Storage: UnifiedStorable> {
        var slots = [Storage.Scope: StorageSlot<Storage>]()
    }

    /// A move, an update or a close waiting until no call runs in its scopes and nothing else holds them.
    private struct WaitingHold {
        let slots: [Slot]
        let continuation: CheckedContinuation<Void, Never>
    }
}

// MARK: - UnifiedStorage + Scope State

extension UnifiedStorage {
    /// What a scope's calls, moves, updates and closes are doing, for tests, which wait for a state instead of sleeping.
    struct ScopeState: Equatable {
        /// Calls running in the scope.
        let runningCalls: Int
        /// Calls waiting for the scope's moves, updates and closes to end.
        let waitingCalls: Int
        /// Whether a move, an update or a close holds the scope.
        let isHeld: Bool
        /// Moves, updates and closes waiting to hold the scope.
        let waitingHolds: Int
    }
}

// MARK: - UnifiedStorage + ScopeStorage

extension UnifiedStorage {
    /// A storage type and scope's coding storage, and the factory's observable one; every call goes through the observable one when there is one.
    struct ScopeStorage<Storage: UnifiedStorable>: Sendable {
        let coding: AsyncCodingStorage<Storage>
        let observable: ObservableStorage<Storage>?

        func fetch<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>) async throws(CodingStorageError<Storage>) -> Value? {
            if let observable {
                return try await observable.fetch(forKey: key)
            }

            return try await coding.fetch(forKey: key)
        }

        func save<Value: CodingValue>(_ value: Value, forKey key: CodingStorageKey<Storage, Value>) async throws(CodingStorageError<Storage>) {
            if let observable {
                try await observable.save(value, forKey: key)
            } else {
                try await coding.save(value, forKey: key)
            }
        }

        func set<Value: CodingValue>(_ value: Value?, forKey key: CodingStorageKey<Storage, Value>) async throws(CodingStorageError<Storage>) {
            if let observable {
                try await observable.set(value, forKey: key)
            } else {
                try await coding.set(value, forKey: key)
            }
        }

        func delete<Value: CodingValue>(forKey key: CodingStorageKey<Storage, Value>) async throws(CodingStorageError<Storage>) {
            if let observable {
                try await observable.delete(forKey: key)
            } else {
                try await coding.delete(forKey: key)
            }
        }

        func clear() async throws(CodingStorageError<Storage>) {
            if let observable {
                try await observable.clear()
            } else {
                try await coding.clear()
            }
        }
    }
}
