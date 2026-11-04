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
