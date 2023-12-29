//
//  KeyValueStoragePropertyWrapper+SwiftUI.swift
//
//
//  Created by Narek Sahakyan on 10.12.23.
//

import SwiftUI
import Combine
import KeyValueStorage
import KeyValueStorageWrapper

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
@propertyWrapper
public struct ObservedStorage<Value: Codable>: DynamicProperty {
    @ObservedObject private var updateTrigger = KeyValueStorageUpdateTrigger()
    private var underlyingStorage: Storage<Value>
    
    public var wrappedValue: Value? {
        get {
            underlyingStorage.wrappedValue
        }
        
        nonmutating set {
            underlyingStorage.wrappedValue = newValue
        }
    }
    
    public var projectedValue: Binding<Value?> {
        .init(
            get: { wrappedValue },
            set: { wrappedValue = $0 }
        )
    }
    
    public init(key: KeyValueStorageKey<Value>, storage: KeyValueStorage = .default) {
        self.underlyingStorage = .init(key: key, storage: storage)
        self.updateTrigger.subscribtion = underlyingStorage.publisher.sink { [weak updateTrigger] _ in
            updateTrigger?.value.toggle()
        }
    }
    
    private final class KeyValueStorageUpdateTrigger: ObservableObject {
        var subscribtion: AnyCancellable?
        @Published var value = false
    }
}
