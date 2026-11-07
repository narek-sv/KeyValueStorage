//
//  Factory+Modifiers.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 04.11.26.
//

// MARK: - Factory + Modifiers

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
