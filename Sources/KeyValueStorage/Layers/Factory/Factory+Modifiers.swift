//
//  Factory+Modifiers.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 04.11.26.
//

// MARK: - Built-in Modifiers

/// `make`, for `Made` only: the type itself, not its scope, since `IsolatedDataStorage<FileStorage>` has `FileStorage`'s.
/// Every cast holds, since `Storage` is `Made`.
struct DataStorageModifier<Made: UnifiedStorable>: UnifiedStorage.Factory.Modifier {
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
struct EveryStorageCoderModifier: UnifiedStorage.Factory.Modifier {
    let coder: any DataCoder

    func coder<Storage: UnifiedStorable>(for storage: Storage, previous: () -> any DataCoder) -> any DataCoder {
        coder
    }
}

/// `coder`, for `Made` only.
struct CoderModifier<Made: UnifiedStorable>: UnifiedStorage.Factory.Modifier {
    let coder: any DataCoder

    func coder<Storage: UnifiedStorable>(for storage: Storage, previous: () -> any DataCoder) -> any DataCoder {
        Storage.self == Made.self ? coder : previous()
    }
}

/// `make`, for `Made` only; every cast holds, since `Storage` is `Made`.
struct CodingStorageModifier<Made: UnifiedStorable>: UnifiedStorage.Factory.Modifier {
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
struct EveryStorageObservableModifier: UnifiedStorage.Factory.Modifier {
    let isObservable: Bool

    func observableStorage<Storage: UnifiedStorable>(
        for coding: AsyncCodingStorage<Storage>,
        previous: () async -> ObservableStorage<Storage>?
    ) async -> ObservableStorage<Storage>? {
        isObservable ? ObservableStorage(coding) : nil
    }
}

/// `make`, for `Made` only; every cast holds, since `Storage` is `Made`.
struct ObservableStorageModifier<Made: UnifiedStorable>: UnifiedStorage.Factory.Modifier {
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
