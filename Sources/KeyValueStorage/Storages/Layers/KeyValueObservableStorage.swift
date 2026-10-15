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
}

open class KeyValueObservableStorage<Storage: KeyValueDataStorage>: KeyValueCodingStorage<Storage>, @unchecked Sendable {
        
    // MARK: Observations

    @CodingStorageActor
    public func stream<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) -> AsyncStream<Value?> {
        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let publisher: KeyValuePublisher<Value?> = publisher(forKey: key)
            let subscription = Subscription(publisher.sink {
                continuation.yield($0)
            })

            continuation.onTermination = { _ in
                subscription.cancel()
            }
        }
    }
    
    @CodingStorageActor
    public func publisher<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) -> KeyValuePublisher<Value?> {
        let mapPublisher = { (publisher: PassthroughSubject<Container, Never>) -> KeyValuePublisher<Value?> in
            KeyValuePublisher(publisher
                .map {
                    if let value = $0.value {
                        return value as? Value
                    }
                    
                    return nil
                }
                .eraseToAnyPublisher())
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
        await send(value, forKey: key)
    }
    
    public override func delete<Value: CodingValue>(forKey key: KeyValueCodingStorageKey<Storage, Value>) async throws {
        try await super.delete(forKey: key)
        await send(nil, forKey: key)
    }
    
    public override func clear() async throws {
        try await super.clear()
        await sendNilToAll()
    }
    
    // MARK: Helpers
    
    @CodingStorageActor
    private func send<Value: CodingValue>(_ value: Value?, forKey key: KeyValueCodingStorageKey<Storage, Value>) {
        publisher(for: key)?.send(.init(value: value))
    }
    
    @CodingStorageActor
    private func sendNilToAll() {
        for observation in (KeyValueObservations.observations[domain] ?? [:]).values {
            if let publisher = observation as? PassthroughSubject<Container, Never> {
                publisher.send(.init())
            }
        }
    }
    
    @CodingStorageActor
    private func publisher(for key: AnyHashable) -> PassthroughSubject<Container, Never>? {
        KeyValueObservations.observations[domain]?[key] as? PassthroughSubject<Container, Never>
    }
    
    // MARK: Inner Hidden Types
    
    private struct Container {
        var value: Any?
    }
}

// MARK: - Helpers

/// Keeps a stream's Combine subscription for its termination handler.
/// Cancelling a Combine subscription is thread-safe, but `AnyCancellable` isn't marked `Sendable`.
private final class Subscription: @unchecked Sendable {
    private let cancellable: AnyCancellable
    
    init(_ cancellable: AnyCancellable) {
        self.cancellable = cancellable
    }
    
    func cancel() {
        cancellable.cancel()
    }
}
