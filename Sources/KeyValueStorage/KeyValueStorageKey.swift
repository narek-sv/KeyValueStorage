//
//  KeyValueStorageKey.swift
//  
//
//  Created by Narek Sahakyan on 7/27/22.
//

/// This struct is intended to uniquely identify the item value, type, and all the necessary info about the storage.
public struct KeyValueStorageKey<T: Codable> {
    
    /// `name` is used to uniquely identify the item.
    let name: String
    
    /// `codingType` is used for properly encoding and decoding the item.
    let codingType: T.Type
    
    /// `storageType` is used for specifing the storage type where the item will be kept.
    let storageType: KeyValueStorageType
    
    /// Initializes the key by specifying the key name and the storage type.
    /// - parameter name: The name of the key.
    /// - parameter storage: The storage type. Default value is `userDefaults`.
    init(name: String, storage: KeyValueStorageType = .userDefaults) {
        self.name = name
        self.codingType = T.self
        self.storageType = storage
    }
}
