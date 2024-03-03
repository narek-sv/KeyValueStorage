//
//  KeyValueObservableStorage.swift
//
//
//  Created by Narek Sahakyan on 30.12.23.
//

import Combine

@ObservableCodingStorageActor
private final class KeyValueObservations {
    fileprivate static var observations = [AnyHashable?: [AnyHashable: Any]]()
}

@ObservableCodingStorageActor
open class KeyValueObservableStorage<Storage: KeyValueDataStorage>: KeyValueCodingStorage<Storage>, @unchecked Sendable {
        
    // MARK: Observations

    public func stream<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) -> AsyncStream<Value?> {
        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let publisher: AnyPublisher<Value?, _> = publisher(forKey: key)
            let subscription = publisher.sink {
                continuation.yield($0)
            }

            continuation.onTermination = { _ in
                subscription.cancel()
            }
        }
    }
    
    public func publisher<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) -> AnyPublisher<Value?, Never> {
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
    
/* AsyncPublisher emits most of the value changes*/
//    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
//    public func asyncPublisher<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) 
//    async -> AsyncPublisher<AnyPublisher<Value?, Never>> {
//        AsyncPublisher(publisher(forKey: key))
//    }
    
    // MARK: Main Functionality
    
    public override func save<Value: CodingValue>(_ value: Value, forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws {
        try await super.save(value, forKey: key)
        publisher(for: key)?.send(.init(value: value))
    }
    
    public override func delete<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws {
        try await super.delete(forKey: key)
        publisher(for: key)?.send(.init())
    }
    
    public override func clear() async throws {
        try await super.clear()

        for observation in (KeyValueObservations.observations[domain] ?? [:]).values {
            if let publisher = observation as? PassthroughSubject<Container, Never> {
                publisher.send(.init())
            }
        }
    }
    
    // MARK: Helpers
    
    private func publisher(for key: AnyHashable) -> PassthroughSubject<Container, Never>? {
        KeyValueObservations.observations[domain]?[key] as? PassthroughSubject<Container, Never>
    }
    
    // MARK: Inner Hidden Types
    
    private struct Container {
        var value: Any?
    }
}

extension AnyCancellable: @unchecked Sendable { }
