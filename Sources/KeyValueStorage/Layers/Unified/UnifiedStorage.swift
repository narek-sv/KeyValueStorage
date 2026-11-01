//
//  UnifiedStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 11.12.23.
//

// MARK: - UnifiedStorage

/// One entry point for every storage, keyed by typed keys.
///
/// - It's safe to call from any thread, task or actor, and calls on storages of different types or scopes never wait for
///   each other; only a `move` holds its two scopes, and calls in them wait until it's done. Only `Sendable` storages
///   compile as keys (`UnifiedStorable`): the built-in storages are thread-safe, and `IsolatedDataStorage` makes any other
///   one shareable.
/// - It creates one storage per storage type and scope, on first use, through its factory.
/// - When its factory makes a storage observable, the changes made through it are published; see `ObservableStorage`.
public final class UnifiedStorage: @unchecked Sendable {

    // MARK: Type Aliases

    public typealias Key = UnifiedStorageKey

    // MARK: Properties

    private let factory: any UnifiedStorageFactory
    /// Guards the slots and the waiting moves; held only to look up or change them, never across an `await`.
    private let lock = Lock()
    /// Each storage type and scope's slot, made on first use and kept.
    private var slots = [AnyHashable: Slot]()
    /// Moves waiting for their scopes, in the order they came.
    private var waitingMoves = [WaitingMove]()

    // MARK: Initializers

    public init(factory: any UnifiedStorageFactory) {
        self.factory = factory
    }

    public init(observable: Bool = false) {
        self.factory = observable ? ObservableUnifiedStorageFactory() : DefaultUnifiedStorageFactory()
    }

    // MARK: Main Functionality

    public func fetch<Storage: UnifiedStorable, Value: CodingValue>(forKey key: Key<Storage, Value>) async throws(CodingStorageError<Storage>) -> Value? {
        try await withScope(key.scope) { (entry: Entry<Storage>) throws(CodingStorageError<Storage>) in
            try await entry.fetch(forKey: .init(key: key.key))
        }
    }

    public func save<Storage: UnifiedStorable, Value: CodingValue>(_ value: Value, forKey key: Key<Storage, Value>) async throws(CodingStorageError<Storage>) {
        try await withScope(key.scope) { (entry: Entry<Storage>) throws(CodingStorageError<Storage>) in
            try await entry.save(value, forKey: .init(key: key.key))
        }
    }

    public func set<Storage: UnifiedStorable, Value: CodingValue>(_ value: Value?, forKey key: Key<Storage, Value>) async throws(CodingStorageError<Storage>) {
        if let value {
            try await save(value, forKey: key)
        } else {
            try await delete(forKey: key)
        }
    }

    public func delete<Storage: UnifiedStorable, Value: CodingValue>(forKey key: Key<Storage, Value>) async throws(CodingStorageError<Storage>) {
        try await withScope(key.scope) { (entry: Entry<Storage>) throws(CodingStorageError<Storage>) in
            try await entry.delete(forKey: CodingStorageKey<Storage, Value>(key: key.key))
        }
    }

    /// Removes every value of the storage type's scope.
    public func clear<Storage: UnifiedStorable>(storage: Storage.Type, forScope scope: Storage.Scope = .default) async throws(CodingStorageError<Storage>) {
        try await withScope(scope) { (entry: Entry<Storage>) throws(CodingStorageError<Storage>) in
            try await entry.clear()
        }
    }

    /// Moves the key's value from `scope` into the key's own scope, such as when a scope's protection or namespace changes:
    /// saves it there, unless a value is there already, then removes it from `scope`.
    ///
    /// - Calls through this `UnifiedStorage` in either scope wait until the move is done, and the move waits for those
    ///   already running, so none of them sees it half done.
    /// - The value is never lost: it's removed from `scope` only once it's saved, and a failed or interrupted move is
    ///   finished by calling it again.
    /// - Warning: Other `UnifiedStorage` instances, storages used directly and other processes, such as app extensions,
    ///   don't wait: move values before they use the key, for example at launch.
    public func move<Storage: UnifiedStorable, Value: CodingValue>(_ key: Key<Storage, Value>, from scope: Storage.Scope) async throws(CodingStorageError<Storage>) {
        guard scope != key.scope else {
            return
        }

        try await withScopes(scope, key.scope) { (source: Entry<Storage>, target: Entry<Storage>) throws(CodingStorageError<Storage>) in
            let codingKey = CodingStorageKey<Storage, Value>(key: key.key)
            guard let value = try await source.fetch(forKey: codingKey) else {
                return
            }

            // A value already there is newer: saved since, or by an earlier move that couldn't remove the old one
            if try await target.fetch(forKey: codingKey) == nil {
                try await target.save(value, forKey: codingKey)
            }

            try await source.delete(forKey: codingKey)
        }
    }

    // MARK: Observation

    /// Changes are delivered on the thread that makes them; see `ObservableStorage`.
    /// - Parameter includingCurrentValue: Whether the publisher first emits the stored value, or `nil` if there's none: the
    ///   value this call reads, or a change published since.
    /// - Returns: `nil` if the factory doesn't make the key's storage observable.
    public func publisher<Storage: UnifiedStorable, Value: CodingValue>(forKey key: Key<Storage, Value>, includingCurrentValue: Bool = true)
    async throws(CodingStorageError<Storage>) -> ValuePublisher<Value?>? {
        try await withScope(key.scope) { (entry: Entry<Storage>) throws(CodingStorageError<Storage>) in
            try await entry.observable?.publisher(forKey: .init(key: key.key), includingCurrentValue: includingCurrentValue)
        }
    }

    /// The stream resumes on the executor of the task that iterates it; see `ObservableStorage`.
    /// - Parameter includingCurrentValue: Whether the stream starts with the stored value, or `nil` if there's none: the
    ///   value this call reads, or a change published since.
    /// - Returns: `nil` if the factory doesn't make the key's storage observable.
    public func stream<Storage: UnifiedStorable, Value: CodingValue>(forKey key: Key<Storage, Value>, includingCurrentValue: Bool = true)
    async throws(CodingStorageError<Storage>) -> AsyncStream<Value?>? {
        try await withScope(key.scope) { (entry: Entry<Storage>) throws(CodingStorageError<Storage>) in
            try await entry.observable?.stream(forKey: .init(key: key.key), includingCurrentValue: includingCurrentValue)
        }
    }

    // MARK: Scopes

    /// Runs `body` with the scope's storage, once no move holds or waits for the scope.
    private func withScope<Storage: UnifiedStorable, T>(
        _ scope: Storage.Scope,
        _ body: (Entry<Storage>) async throws(CodingStorageError<Storage>) -> T
    ) async throws(CodingStorageError<Storage>) -> T {
        let slot = await enterCall(UnderlyingStorageKey<Storage>(scope: scope))
        defer {
            leaveCall(slot)
        }

        return try await body(entry(in: slot, for: scope))
    }

    /// Runs `body` with both scopes' storages, once no call runs in either; calls in them wait meanwhile.
    private func withScopes<Storage: UnifiedStorable>(
        _ first: Storage.Scope,
        _ second: Storage.Scope,
        _ body: (Entry<Storage>, Entry<Storage>) async throws(CodingStorageError<Storage>) -> Void
    ) async throws(CodingStorageError<Storage>) {
        let slots = lock.withLock {
            [slot(for: UnderlyingStorageKey<Storage>(scope: first)), slot(for: UnderlyingStorageKey<Storage>(scope: second))]
        }

        await enterMove(slots)
        defer {
            leaveMove(slots)
        }

        try await body(entry(in: slots[0], for: first), entry(in: slots[1], for: second))
    }

    /// Under the lock: the scope's slot, made on first use.
    private func slot(for key: AnyHashable) -> Slot {
        if let slot = slots[key] {
            return slot
        }

        let slot = Slot()
        slots[key] = slot
        return slot
    }

    private func enterCall(_ key: AnyHashable) async -> Slot {
        let (slot, entered) = lock.withLock { () -> (Slot, Bool) in
            let found = self.slot(for: key)
            guard found.admitsCalls else {
                return (found, false)
            }

            found.calls += 1
            return (found, true)
        }

        guard !entered else {
            return slot
        }

        // Admitted at once if the scope was freed since the check above, so a move that ends meanwhile can't miss this call
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let calls = lock.withLock {
                slot.waitingCalls.append(continuation)
                return admitCalls(in: slot)
            }

            resume(calls)
        }

        return slot
    }

    private func leaveCall(_ slot: Slot) {
        let moves = lock.withLock {
            slot.calls -= 1
            return admitMoves()
        }

        resume(moves)
    }

    private func enterMove(_ slots: [Slot]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let moves = lock.withLock {
                slots.forEach { $0.waitingMoves += 1 }
                waitingMoves.append(WaitingMove(slots: slots, continuation: continuation))
                return admitMoves()
            }

            resume(moves)
        }
    }

    private func leaveMove(_ slots: [Slot]) {
        let (calls, moves) = lock.withLock {
            var calls = [CheckedContinuation<Void, Never>]()
            for slot in slots {
                slot.isMoving = false
                calls += admitCalls(in: slot)
            }

            return (calls, admitMoves())
        }

        resume(calls + moves)
    }

    /// After unlocking: resumes the calls and moves let in under the lock.
    private func resume(_ continuations: [CheckedContinuation<Void, Never>]) {
        continuations.forEach { $0.resume() }
    }

    /// Under the lock: lets in the slot's waiting calls once no move holds or waits for it; returns them to resume after unlocking.
    private func admitCalls(in slot: Slot) -> [CheckedContinuation<Void, Never>] {
        guard slot.admitsCalls else {
            return []
        }

        let calls = slot.waitingCalls
        slot.calls += calls.count
        slot.waitingCalls = []
        return calls
    }

    /// Under the lock: lets in every waiting move whose scopes are free, oldest first; returns them to resume after unlocking.
    private func admitMoves() -> [CheckedContinuation<Void, Never>] {
        var admitted = [CheckedContinuation<Void, Never>]()
        waitingMoves.removeAll { move in
            guard move.slots.allSatisfy(\.admitsMove) else {
                return false
            }

            for slot in move.slots {
                slot.isMoving = true
                slot.waitingMoves -= 1
            }

            admitted.append(move.continuation)
            return true
        }

        return admitted
    }

    // MARK: Storages

    /// The slot's storage, created on first use; concurrent first calls share one creation. Failures aren't kept, so a
    /// later call can retry.
    private func entry<Storage: UnifiedStorable>(in slot: Slot, for scope: Storage.Scope) async throws(CodingStorageError<Storage>) -> Entry<Storage> {
        let factory = factory
        let task = lock.withLock { () -> CreationTask<Storage> in
            if let task = slot.creation as? CreationTask<Storage> {
                return task
            }

            let task = CreationTask<Storage> {
                do throws(Storage.Error) {
                    let dataStorage: Storage = try await factory.dataStorage(for: scope)
                    let coding = await factory.codingStorage(for: dataStorage)
                    return .success(Entry(coding: coding, observable: await factory.observableStorage(for: coding)))
                } catch {
                    return .failure(error)
                }
            }

            slot.creation = task
            return task
        }

        switch await task.value {
        case let .success(entry):
            return entry
        case let .failure(error):
            lock.withLock {
                if slot.creation as? CreationTask<Storage> == task {
                    slot.creation = nil
                }
            }

            throw .storage(error)
        }
    }

    /// Creation can't fail with a typed error inside a `Task`, so the task returns its outcome instead.
    private typealias CreationTask<Storage: UnifiedStorable> = Task<Result<Entry<Storage>, Storage.Error>, Never>
}

// MARK: - UnifiedStorage + Slot

extension UnifiedStorage {
    /// A storage type and scope: its storage's creation, and the calls and moves that use it. Guarded by the lock.
    private final class Slot: @unchecked Sendable {
        /// The storage's creation task; `nil` before the first call, and after a failed creation.
        var creation: (any Sendable)?
        /// Calls running in the scope.
        var calls = 0
        /// Whether a move holds the scope.
        var isMoving = false
        /// Moves waiting for the scope; new calls wait behind them, so a move never waits forever.
        var waitingMoves = 0
        /// Calls waiting for the scope's moves to end.
        var waitingCalls = [CheckedContinuation<Void, Never>]()

        var admitsCalls: Bool {
            !isMoving && waitingMoves == 0
        }

        var admitsMove: Bool {
            !isMoving && calls == 0
        }
    }

    /// A move waiting until no call runs in its scopes and no other move holds them.
    private struct WaitingMove {
        let slots: [Slot]
        let continuation: CheckedContinuation<Void, Never>
    }
}

// MARK: - UnifiedStorage + Entry

extension UnifiedStorage {
    /// A storage type and scope's coding storage, and the factory's observable one; every call goes through the observable one when there is one.
    private struct Entry<Storage: UnifiedStorable>: Sendable {
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

// MARK: - UnifiedStorage + UnderlyingStorageKey

extension UnifiedStorage {
    /// Keys of other storage types are other types, so `==` compares only the scope; the hash also mixes in the storage type,
    /// because the cache holds every storage type's keys as `AnyHashable`.
    private struct UnderlyingStorageKey<Storage: UnifiedStorable>: Hashable, Sendable {
        let scope: Storage.Scope

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.scope == rhs.scope
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(scope)
            hasher.combine(ObjectIdentifier(Storage.self))
        }
    }
}
