//
//  KeyValueStoragePropertyWrapper.swift
//
//
//  Created by Narek Sahakyan on 09.12.23.
//

import Combine
import KeyValueStorageLegacy

fileprivate final class KeyValueStoragePreferences {
    static let shared = KeyValueStoragePreferences()
    
    var publishers = [AnyHashable: Any]()
}
 
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
@propertyWrapper
public struct Storage<Value: Codable> {
    typealias Key = KeyValueStorageKey<Value>
    
    private let preferences = KeyValueStoragePreferences.shared
    private let publisherKey: KeyValueStoragePublisherKey
    private let storage: KeyValueStorage
    private let key: Key
    
    private var _publisher: PassthroughSubject<Value?, Never> {
        (preferences.publishers[publisherKey] as! PassthroughSubject<Value?, Never>)
    }
    
    public var wrappedValue: Value? {
        get {
            storage.fetch(forKey: key)
        }
        
        nonmutating set {
            storage.set(newValue, forKey: key)
            _publisher.send(newValue)
        }
    }
    
    public var publisher: AnyPublisher<Value?, Never> {
        _publisher.eraseToAnyPublisher()
    }
        
    public init(key: KeyValueStorageKey<Value>, storage: KeyValueStorage = .default) {
        self.key = key
        self.storage = storage
        self.publisherKey = .init(serviceName: storage.serviceName, key: key)
        
        if preferences.publishers[publisherKey] == nil {
            preferences.publishers[publisherKey] = PassthroughSubject<Value?, Never>()
        }
    }

    private struct KeyValueStoragePublisherKey: Hashable {
        let serviceName: String
        let key: Key
    }
}
