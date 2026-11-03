//
//  UnifiedStorage+Factory.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

// MARK: - UnifiedStorage + Factory

public extension UnifiedStorage {
    /// Makes each storage type and scope's storages, in steps: creates the storage with its `init(scope:)`, picks
    /// `RawDataCoder`, wraps both in an `AsyncCodingStorage`, and doesn't observe it. Start from `default` and add a
    /// modifier for each change, for every storage type or for one.
    ///
    /// The last modifier decides: each gets what the ones before it make, and returns it as is, changed or replaced, so add
    /// the modifiers for every storage type first. A modifier for one type changes only that exact type:
    /// `IsolatedDataStorage<FileStorage>`, which has `FileStorage`'s scopes, isn't `FileStorage`.
    struct Factory: Sendable {
        private var modifiers = [any Modifier]()

        /// No modifiers: every step's default.
        public static var `default`: Self {
            Self()
        }

        /// Adds a modifier of your own, after the others, so it decides over them.
        public func modifier(_ modifier: some Modifier) -> Self {
            var factory = self
            factory.modifiers.append(modifier)
            return factory
        }
    }
}

// MARK: - UnifiedStorage.Factory + Modifier

public extension UnifiedStorage.Factory {
    /// A change to how a factory makes storages, for every storage type: implement the steps it changes. Each step gets
    /// `previous`, what the modifiers before it make, and returns it as is, changed or replaced; the steps a modifier doesn't
    /// implement return it. Each call to `previous` makes it anew, such as another database connection.
    /// - Note: Let Xcode complete each method: one that differs in any way, even in an argument label, compiles but is never
    ///   called.
    protocol Modifier: Sendable {
        func dataStorage<Storage: UnifiedStorable>(
            for scope: Storage.Scope,
            previous: () async throws(Storage.Error) -> Storage
        ) async throws(Storage.Error) -> Storage

        func coder<Storage: UnifiedStorable>(
            for storage: Storage,
            previous: () -> any DataCoder
        ) -> any DataCoder

        func codingStorage<Storage: UnifiedStorable>(
            for storage: Storage,
            coder: any DataCoder,
            previous: () async -> AsyncCodingStorage<Storage>
        ) async -> AsyncCodingStorage<Storage>

        /// `nil` for a storage whose changes aren't published.
        func observableStorage<Storage: UnifiedStorable>(
            for coding: AsyncCodingStorage<Storage>,
            previous: () async -> ObservableStorage<Storage>?
        ) async -> ObservableStorage<Storage>?
    }
}

public extension UnifiedStorage.Factory.Modifier {
    func dataStorage<Storage: UnifiedStorable>(
        for scope: Storage.Scope,
        previous: () async throws(Storage.Error) -> Storage
    ) async throws(Storage.Error) -> Storage {
        try await previous()
    }

    func coder<Storage: UnifiedStorable>(for storage: Storage, previous: () -> any DataCoder) -> any DataCoder {
        previous()
    }

    func codingStorage<Storage: UnifiedStorable>(
        for storage: Storage,
        coder: any DataCoder,
        previous: () async -> AsyncCodingStorage<Storage>
    ) async -> AsyncCodingStorage<Storage> {
        await previous()
    }

    func observableStorage<Storage: UnifiedStorable>(
        for coding: AsyncCodingStorage<Storage>,
        previous: () async -> ObservableStorage<Storage>?
    ) async -> ObservableStorage<Storage>? {
        await previous()
    }
}

// MARK: - UnifiedStorage.Factory + Modifiers

public extension UnifiedStorage.Factory {
    /// Creates `Storage`'s storages with `make`, such as with a custom locator or backing store.
    /// - Note: Swift doesn't infer a closure's typed `throws`: spell out the error type, `{ scope throws(FileStorage.Error) in … }`.
    func dataStorage<Storage: UnifiedStorable>(
        for _: Storage.Type,
        _ make: @escaping @Sendable (Storage.Scope) async throws(Storage.Error) -> Storage
    ) -> Self {
        modifier(DataStorageModifier(make: make))
    }

    /// Codes every storage's values with `coder`.
    func coder(_ coder: any DataCoder) -> Self {
        modifier(EveryStorageCoderModifier(coder: coder))
    }

    /// Codes `Storage`'s values with `coder`.
    func coder<Storage: UnifiedStorable>(_ coder: any DataCoder, for _: Storage.Type) -> Self {
        modifier(CoderModifier<Storage>(coder: coder))
    }

    /// Makes `Storage`'s coding storages with `make`, from each storage and its coder, such as your own `AsyncCodingStorage`
    /// subclass.
    func codingStorage<Storage: UnifiedStorable>(
        for _: Storage.Type,
        _ make: @escaping @Sendable (Storage, any DataCoder) -> AsyncCodingStorage<Storage>
    ) -> Self {
        modifier(CodingStorageModifier(make: make))
    }

    /// Publishes every storage's changes through `ObservableStorage`, or none.
    func observable(_ isObservable: Bool = true) -> Self {
        modifier(EveryStorageObservableModifier(isObservable: isObservable))
    }

    /// Publishes `Storage`'s changes through `ObservableStorage`, or not.
    func observable<Storage: UnifiedStorable>(_ isObservable: Bool = true, for type: Storage.Type) -> Self {
        observableStorage(for: type) { coding in
            isObservable ? ObservableStorage(coding) : nil
        }
    }

    /// Observes `Storage`'s storages through what `make` returns, such as an `ObservableStorage` subclass, or `nil` for none.
    func observableStorage<Storage: UnifiedStorable>(
        for _: Storage.Type,
        _ make: @escaping @Sendable (AsyncCodingStorage<Storage>) -> ObservableStorage<Storage>?
    ) -> Self {
        modifier(ObservableStorageModifier(make: make))
    }
}

// MARK: - UnifiedStorage.Factory + Making

/// Each step asks the last modifier, whose `previous` asks the factory without it, down to the defaults.
extension UnifiedStorage.Factory {
    func makeDataStorage<Storage: UnifiedStorable>(for scope: Storage.Scope) async throws(Storage.Error) -> Storage {
        guard let last = modifiers.last else {
            return try await Storage(scope: scope)
        }

        return try await last.dataStorage(for: scope) { () async throws(Storage.Error) -> Storage in
            try await previous.makeDataStorage(for: scope)
        }
    }

    func makeCoder<Storage: UnifiedStorable>(for storage: Storage) -> any DataCoder {
        guard let last = modifiers.last else {
            return RawDataCoder()
        }

        return last.coder(for: storage) {
            previous.makeCoder(for: storage)
        }
    }

    func makeCodingStorage<Storage: UnifiedStorable>(for storage: Storage, coder: any DataCoder) async -> AsyncCodingStorage<Storage> {
        guard let last = modifiers.last else {
            return AsyncCodingStorage(storage: storage, coder: coder)
        }

        return await last.codingStorage(for: storage, coder: coder) {
            await previous.makeCodingStorage(for: storage, coder: coder)
        }
    }

    func makeObservableStorage<Storage: UnifiedStorable>(for coding: AsyncCodingStorage<Storage>) async -> ObservableStorage<Storage>? {
        guard let last = modifiers.last else {
            return nil
        }

        return await last.observableStorage(for: coding) {
            await previous.makeObservableStorage(for: coding)
        }
    }

    /// This factory without its last modifier.
    private var previous: Self {
        var factory = self
        factory.modifiers.removeLast()
        return factory
    }
}

// MARK: - Built-in Modifiers

/// `make`, for `Made` only: the type itself, not its scope, since `IsolatedDataStorage<FileStorage>` has `FileStorage`'s.
/// Every cast holds, since `Storage` is `Made`.
private struct DataStorageModifier<Made: UnifiedStorable>: UnifiedStorage.Factory.Modifier {
    let make: @Sendable (Made.Scope) async throws(Made.Error) -> Made

    func dataStorage<Storage: UnifiedStorable>(
        for scope: Storage.Scope,
        previous: () async throws(Storage.Error) -> Storage
    ) async throws(Storage.Error) -> Storage {
        guard Storage.self == Made.self else {
            return try await previous()
        }

        do {
            return try await make(scope as! Made.Scope) as! Storage
        } catch {
            throw error as! Storage.Error
        }
    }
}

/// `coder`, for every storage.
private struct EveryStorageCoderModifier: UnifiedStorage.Factory.Modifier {
    let coder: any DataCoder

    func coder<Storage: UnifiedStorable>(for storage: Storage, previous: () -> any DataCoder) -> any DataCoder {
        coder
    }
}

/// `coder`, for `Made` only.
private struct CoderModifier<Made: UnifiedStorable>: UnifiedStorage.Factory.Modifier {
    let coder: any DataCoder

    func coder<Storage: UnifiedStorable>(for storage: Storage, previous: () -> any DataCoder) -> any DataCoder {
        Storage.self == Made.self ? coder : previous()
    }
}

/// `make`, for `Made` only; every cast holds, since `Storage` is `Made`.
private struct CodingStorageModifier<Made: UnifiedStorable>: UnifiedStorage.Factory.Modifier {
    let make: @Sendable (Made, any DataCoder) -> AsyncCodingStorage<Made>

    func codingStorage<Storage: UnifiedStorable>(
        for storage: Storage,
        coder: any DataCoder,
        previous: () async -> AsyncCodingStorage<Storage>
    ) async -> AsyncCodingStorage<Storage> {
        guard Storage.self == Made.self else {
            return await previous()
        }

        return make(storage as! Made, coder) as! AsyncCodingStorage<Storage>
    }
}

/// An `ObservableStorage`, or none, for every storage.
private struct EveryStorageObservableModifier: UnifiedStorage.Factory.Modifier {
    let isObservable: Bool

    func observableStorage<Storage: UnifiedStorable>(
        for coding: AsyncCodingStorage<Storage>,
        previous: () async -> ObservableStorage<Storage>?
    ) async -> ObservableStorage<Storage>? {
        isObservable ? ObservableStorage(coding) : nil
    }
}

/// `make`, for `Made` only; every cast holds, since `Storage` is `Made`.
private struct ObservableStorageModifier<Made: UnifiedStorable>: UnifiedStorage.Factory.Modifier {
    let make: @Sendable (AsyncCodingStorage<Made>) -> ObservableStorage<Made>?

    func observableStorage<Storage: UnifiedStorable>(
        for coding: AsyncCodingStorage<Storage>,
        previous: () async -> ObservableStorage<Storage>?
    ) async -> ObservableStorage<Storage>? {
        guard Storage.self == Made.self else {
            return await previous()
        }

        return make(coding as! AsyncCodingStorage<Made>).map { $0 as! ObservableStorage<Storage> }
    }
}
