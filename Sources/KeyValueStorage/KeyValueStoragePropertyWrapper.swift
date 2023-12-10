//
//  KeyValueStoragePropertyWrapper.swift
//
//
//  Created by Narek Sahakyan on 09.12.23.
//

import Combine

fileprivate final class KeyValueStoragePreferences {
    static let shared = KeyValueStoragePreferences()
    
    var publishers = [AnyHashable: Any]()
}
 
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
@propertyWrapper
open class Storage<Value: Codable> {
    typealias Key = KeyValueStorageKey<Value>
    
    private let preferences: KeyValueStoragePreferences = .shared
    private let storage: KeyValueStorage
    private let key: Key
    
    private var publisher: PassthroughSubject<Value?, Never> {
        (preferences.publishers[key] as! PassthroughSubject<Value?, Never>)
    }
    
    public var wrappedValue: Value? {
        get {
            return storage.fetch(forKey: key)
        }
        
        set {
            storage.set(newValue, forKey: key)
            publisher.send(newValue)
        }
    }
    
    public var projectedValue: AnyPublisher<Value?, Never> {
        publisher.eraseToAnyPublisher()
    }
        
    public init(key: KeyValueStorageKey<Value>, storage: KeyValueStorage = .default) {
        self.key = key
        self.storage = .default
        
        if preferences.publishers[key] == nil {
            preferences.publishers[key] = PassthroughSubject<Value?, Never>()
        }
    }
}
