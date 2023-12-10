//
//  KeychainHelper.swift
//  
//
//  Created by Narek Sahakyan on 7/27/22.
//

import Foundation
import Security

/// A wrapper class which allows to use Keychain it in a similar manner to User Defaults.
final class KeychainHelper {
    
    /// `serviceName` is used to uniquely identify this keychain accessor.
    private(set) var serviceName: String
    
    /// `accessGroup` is used to identify which Keychain Access Group this entry belongs to. This allows you to use shared keychain access between different applications.
    private(set) var accessGroup: String?
    
    init(serviceName: String, accessGroup: String? = nil) {
        self.serviceName = serviceName
        self.accessGroup = accessGroup
    }
    
    /// Returns a Data object for a specified key.
    ///
    /// - parameter forKey: The key to lookup data for.
    /// - parameter withAccessibility: Optional accessibility to use when retrieving the keychain item.
    /// - parameter isSynchronizable: A bool that describes if the item should be synchronizable, to be synched with the iCloud. If none is provided, will default to false.
    /// - returns: The Data object associated with the key if it exists. If no data exists, returns nil.
    func get(forKey key: String,
             withAccessibility accessibility: KeychainAccessibility? = nil,
             isSynchronizable: Bool = false) -> Data? {
        var keychainQueryDictionary = query(forKey: key, withAccessibility: accessibility, isSynchronizable: isSynchronizable)
        keychainQueryDictionary[KeychainHelper.matchLimit] = kSecMatchLimitOne
        keychainQueryDictionary[KeychainHelper.returnData] = kCFBooleanTrue
        
        // Search
        var result: AnyObject?
        let status = SecItemCopyMatching(keychainQueryDictionary as CFDictionary, &result)
        
        return status == noErr ? result as? Data : nil
    }
    
    /// Save a Data object to the keychain associated with a specified key. If data already exists for the given key, the data will be overwritten with the new value.
    ///
    /// - parameter value: The Data object to save.
    /// - parameter forKey: The key to save the object under.
    /// - parameter withAccessibility: Optional accessibility to use when setting the keychain item.
    /// - parameter isSynchronizable: A bool that describes if the item should be synchronizable, to be synched with the iCloud. If none is provided, will default to false.
    /// - returns: True if the save was successful, false otherwise.
    @discardableResult
    func set(_ value: Data,
             forKey key: String,
             withAccessibility accessibility: KeychainAccessibility? = nil,
             isSynchronizable: Bool = false) -> Bool {
        var keychainQueryDictionary = query(forKey: key, withAccessibility: accessibility, isSynchronizable: isSynchronizable)
        keychainQueryDictionary[KeychainHelper.valueData] = value
        keychainQueryDictionary[KeychainHelper.attrAccessible] = accessibility?.key ?? KeychainAccessibility.whenUnlocked.key
        
        let status = SecItemAdd(keychainQueryDictionary as CFDictionary, nil)
        if status == errSecSuccess {
            return true
        } else if status == errSecDuplicateItem {
            return update(value, forKey: key, withAccessibility: accessibility, isSynchronizable: isSynchronizable)
        }
        
        return false
    }
    
    /// Remove an object associated with a specified key. If re-using a key but with a different accessibility, first remove the previous key value using removeObjectForKey(:withAccessibility) using the same accessibilty it was saved with.
    ///
    /// - parameter forKey: The key value to remove data for.
    /// - parameter withAccessibility: Optional accessibility level to use when looking up the keychain item.
    /// - parameter isSynchronizable: A bool that describes if the item should be synchronizable, to be synched with the iCloud. If none is provided, will default to false.
    /// - returns: True if successful, false otherwise.
    @discardableResult
    func remove(forKey key: String,
                withAccessibility accessibility: KeychainAccessibility? = nil,
                isSynchronizable: Bool = false) -> Bool {
        let keychainQueryDictionary = query(forKey: key, withAccessibility: accessibility, isSynchronizable: isSynchronizable)
        
        let status = SecItemDelete(keychainQueryDictionary as CFDictionary)
        return status == errSecSuccess
    }
    
    /// Remove all keychain data added through KeychainWrapper. This will only delete items matching the currnt ServiceName and AccessGroup if one is set.
    /// - returns: True if successful, false otherwise.
    @discardableResult
    func removeAll() -> Bool {
        var keychainQueryDictionary: [String: Any] = [KeychainHelper.class: kSecClassGenericPassword]
        keychainQueryDictionary[KeychainHelper.attrService] = serviceName
        keychainQueryDictionary[KeychainHelper.attrAccessGroup] = accessGroup
        
        let status = SecItemDelete(keychainQueryDictionary as CFDictionary)
        return status == errSecSuccess
    }
    
    // MARK: - Helpers
    
    private func update(_ value: Data,
                        forKey key: String,
                        withAccessibility accessibility: KeychainAccessibility? = nil,
                        isSynchronizable: Bool = false) -> Bool {
        let updateDictionary = [KeychainHelper.valueData: value]
        var keychainQueryDictionary = query(forKey: key, withAccessibility: accessibility, isSynchronizable: isSynchronizable)
        keychainQueryDictionary[KeychainHelper.attrAccessible] = accessibility?.key
        
        let status = SecItemUpdate(keychainQueryDictionary as CFDictionary, updateDictionary as CFDictionary)
        return status == errSecSuccess
    }
    
    private func query(forKey key: String,
                       withAccessibility accessibility: KeychainAccessibility? = nil,
                       isSynchronizable: Bool = false) -> [String: Any] {
        var keychainQueryDictionary: [String: Any] = [KeychainHelper.class: kSecClassGenericPassword]
        let encodedIdentifier = key.data(using: .utf8)
        
        keychainQueryDictionary[KeychainHelper.attrService] = serviceName
        keychainQueryDictionary[KeychainHelper.attrAccessible] = accessibility?.key
        keychainQueryDictionary[KeychainHelper.attrAccessGroup] = accessGroup
        keychainQueryDictionary[KeychainHelper.attrGeneric] = encodedIdentifier
        keychainQueryDictionary[KeychainHelper.attrAccount] = encodedIdentifier
        keychainQueryDictionary[KeychainHelper.attrSynchronizable] = isSynchronizable ? kCFBooleanTrue : kCFBooleanFalse
        return keychainQueryDictionary
    }
}

// MARK: - Keys

extension KeychainHelper {
    private static let `class`              = kSecClass as String
    private static let matchLimit           = kSecMatchLimit as String
    private static let returnData           = kSecReturnData as String
    private static let valueData            = kSecValueData as String
    private static let attrAccessible       = kSecAttrAccessible as String
    private static let attrService          = kSecAttrService as String
    private static let attrGeneric          = kSecAttrGeneric as String
    private static let attrAccount          = kSecAttrAccount as String
    private static let attrAccessGroup      = kSecAttrAccessGroup as String
    private static let attrSynchronizable   = kSecAttrSynchronizable as String
    private static let returnAttributes     = kSecReturnAttributes as String
}

// MARK: - Accessibility

public enum KeychainAccessibility {
    case afterFirstUnlock
    case afterFirstUnlockThisDeviceOnly
    case whenPasscodeSetThisDeviceOnly
    case whenUnlocked
    case whenUnlockedThisDeviceOnly
//  case always                   (deprecated)
//  case alwaysThisDeviceOnly     (deprecated)
    
    var key: String {
        switch self {
        case .afterFirstUnlock:                 return kSecAttrAccessibleAfterFirstUnlock as String
        case .afterFirstUnlockThisDeviceOnly:   return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        case .whenPasscodeSetThisDeviceOnly:    return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String
        case .whenUnlocked:                     return kSecAttrAccessibleWhenUnlocked as String
        case .whenUnlockedThisDeviceOnly:       return kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        }
    }
}
