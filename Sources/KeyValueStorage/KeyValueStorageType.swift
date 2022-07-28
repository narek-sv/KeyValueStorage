//
//  KeyValueStorageType.swift
//  
//
//  Created by Narek Sahakyan on 7/27/22.
//

public enum KeyValueStorageType: Equatable {
    case userDefaults
    case inMemory(isStatic: Bool = false)
    case keychain(accessibility: KeychainAccessibility = .whenUnlocked, isSynchronizable: Bool = false)
}
