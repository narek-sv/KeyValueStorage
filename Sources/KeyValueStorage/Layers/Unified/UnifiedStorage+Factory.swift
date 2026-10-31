//
//  UnifiedStorage+Factory.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

// MARK: - UnifiedStorageFactory

/// Creates `UnifiedStorage`'s storages, one per storage type and scope; each requirement has a default, so a factory
/// implements only what it changes.
public protocol UnifiedStorageFactory: Sendable {
    func dataStorage<Storage: UnifiedStorable>(for scope: Storage.Scope) async throws(Storage.Error) -> Storage
    func coder<Storage: UnifiedStorable>(for storage: Storage) -> any DataCoder
    func codingStorage<Storage: UnifiedStorable>(for storage: Storage) async -> AsyncCodingStorage<Storage>
    /// `nil` for a storage whose changes aren't published.
    func observableStorage<Storage: UnifiedStorable>(for storage: AsyncCodingStorage<Storage>) async -> ObservableStorage<Storage>?
}

// MARK: - UnifiedStorageFactory + Defaults

public extension UnifiedStorageFactory {
    /// The storage's own `init(scope:)`.
    func dataStorage<Storage: UnifiedStorable>(for scope: Storage.Scope) async throws(Storage.Error) -> Storage {
        try await Storage(scope: scope)
    }

    /// `RawDataCoder`, for every storage.
    func coder<Storage: UnifiedStorable>(for storage: Storage) -> any DataCoder {
        RawDataCoder()
    }

    /// An `AsyncCodingStorage` with `coder(for:)`.
    func codingStorage<Storage: UnifiedStorable>(for storage: Storage) async -> AsyncCodingStorage<Storage> {
        AsyncCodingStorage(storage: storage, coder: coder(for: storage))
    }

    /// `nil`: changes aren't published.
    func observableStorage<Storage: UnifiedStorable>(for storage: AsyncCodingStorage<Storage>) async -> ObservableStorage<Storage>? {
        nil
    }
}

// MARK: - DefaultUnifiedStorageFactory

/// Every default: each storage from its `init(scope:)`, with `RawDataCoder`, and not observable.
public struct DefaultUnifiedStorageFactory: UnifiedStorageFactory {
    public init() { }
}

// MARK: - ObservableUnifiedStorageFactory

/// The defaults, with every storage observable through `ObservableStorage`.
public struct ObservableUnifiedStorageFactory: UnifiedStorageFactory {
    public init() { }

    public func observableStorage<Storage: UnifiedStorable>(for storage: AsyncCodingStorage<Storage>) async -> ObservableStorage<Storage>? {
        ObservableStorage(storage)
    }
}
