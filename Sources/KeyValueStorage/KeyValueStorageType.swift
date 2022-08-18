//
//  KeyValueStorageType.swift
//  
//
//  Created by Narek Sahakyan on 7/27/22.
//

/// This enum contains all the supported storage types
public enum KeyValueStorageType: Equatable {
    
    /// This storage type persists only within an app session
    case inMemory
    
    /// This storage type persists within the whole app lifetime
    case userDefaults
    
    /// This storage type keeps the items in a secure storage and persists even app re-installations
    /// - parameter accessibility: Accessibility to use when retrieving the keychain item.
    /// - parameter isSynchronizable: A bool that describes if the item should be synchronizable, to be synched with the iCloud.
    case keychain(accessibility: KeychainAccessibility = .whenUnlocked, isSynchronizable: Bool = false)
}
