//
//  Factory+Making.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 04.11.26.
//

// MARK: - Factory + Making

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
