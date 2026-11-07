//
//  Factory+Modifier.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 04.11.26.
//

// MARK: - Factory + Modifier

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
