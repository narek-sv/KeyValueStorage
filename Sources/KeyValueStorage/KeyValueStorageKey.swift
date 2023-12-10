//
//  KeyValueStorageKey.swift
//  
//
//  Created by Narek Sahakyan on 7/27/22.
//

/// This struct is intended to uniquely identify the item value, type, and all the necessary info about the storage.
public struct KeyValueStorageKey<T: Codable> {
    
    /// `name` is used to uniquely identify the item.
    public let name: String
    
    /// `codingType` is used for properly encoding and decoding the item.
    public let codingType: T.Type
    
    /// `storageType` is used for specifing the storage type where the item will be kept.
    public let storageType: KeyValueStorageType
    
    /// Initializes the key by specifying the key name and the storage type.
    /// - parameter name: The name of the key.
    /// - parameter storage: The storage type. Default value is `userDefaults`.
    public init(name: String, storage: KeyValueStorageType = .userDefaults) {
        self.name = name
        self.codingType = T.self
        self.storageType = storage
    }
}

extension KeyValueStorageKey: Hashable {
    public static func == (lhs: KeyValueStorageKey<T>, rhs: KeyValueStorageKey<T>) -> Bool {
        lhs.name == rhs.name && 
        lhs.storageType == rhs.storageType &&
        lhs.codingType == rhs.codingType

    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(storageType)
        hasher.combine(String(describing: codingType))
    }
}
