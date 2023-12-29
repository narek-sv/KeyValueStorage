//
//  KeyValueObservableStorage.swift
//
//
//  Created by Narek Sahakyan on 30.12.23.
//

import Combine

@CodingStorageActor
private final class KeyValueObservations {
    fileprivate static var observations = [AnyHashable?: [AnyHashable: Any]]()
    fileprivate static var cancellables = Set<AnyCancellable>()
}

@CodingStorageActor
open class KeyValueObservableStorage<Storage: KeyValueDataStorage>: KeyValueCodingStorage<Storage>, @unchecked Sendable {
    private var cancellables = Set<AnyCancellable>()
    
    public func stream<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) async -> AsyncStream<Value?> {
        let publisher: AnyPublisher<Value?, _> = await publisher(forKey: key)
        return .init { continuation in
            publisher
                .sink {
                    continuation.yield($0)
                }
                .store(in: &KeyValueObservations.cancellables)
            }
    }
    
    public func publisher<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) async -> AnyPublisher<Value?, Never> {
        let mapPublisher = { (publisher: PassthroughSubject<Container, Never>) -> AnyPublisher<Value?, Never> in
            publisher
                .map {
                    if let value = $0.value {
                        return value as? Value
                    }
                    
                    return nil
                }
                .eraseToAnyPublisher()
        }
        
        if let observation = KeyValueObservations.observations[domain]?[key],
           let publisher = observation as? PassthroughSubject<Container, Never> {
            return mapPublisher(publisher)
        }
        
        if KeyValueObservations.observations[domain] == nil {
            KeyValueObservations.observations[domain] = [:]
        }
        
        let publisher = PassthroughSubject<Container, Never>()
        KeyValueObservations.observations[domain]?[key] = publisher
        return mapPublisher(publisher)
    }
    
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    func asyncPublisher<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) async -> AsyncPublisher<AnyPublisher<Value?, Never>> {
        await AsyncPublisher(publisher(forKey: key))
    }
    
    public override func save<Value: CodingValue>(_ value: Value, forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws {
        try await super.save(value, forKey: key)
        publisher(for: key.key)?.send(.init(value: value))
    }
    
    public override func delete<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws {
        try await super.delete(forKey: key)
        publisher(for: key.key)?.send(.init())
    }
    
    public override func clear() async throws {
        try await super.clear()

        for observation in KeyValueObservations.observations[domain].unwrapped([:]).values {
            if let publisher = observation as? PassthroughSubject<Container, Never> {
                publisher.send(.init())
            }
        }
    }
    
    private func publisher(for key: Storage.Key) -> PassthroughSubject<Container, Never>? {
        KeyValueObservations.observations[domain]?[key] as? PassthroughSubject<Container, Never>
    }
}

private struct Container {
    var value: Any?
}

extension AnyPublisher: @unchecked Sendable { }
