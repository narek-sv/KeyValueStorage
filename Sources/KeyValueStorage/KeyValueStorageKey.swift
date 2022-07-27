//
//  KeyValueStorageKey.swift
//  
//
//  Created by Narek Sahakyan on 7/27/22.
//

public struct KeyValueStorageKey<T: Codable> {
    let name: String
    let codingType: T.Type
    let storageType: KeyValueStorageType
    
    init(name: String, storage: KeyValueStorageType = .userDefaults) {
        self.name = name
        self.codingType = T.self
        self.storageType = storage
    }
}
