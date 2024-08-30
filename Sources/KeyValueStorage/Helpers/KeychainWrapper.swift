//
//  KeychainWrapper.swift
//
//
//  Created by Narek Sahakyan on 7/27/22.
//

import Foundation
import Security

enum KeychainWrapperError: Error {
    case status(OSStatus)
}

/// A wrapper class which allows to use Keychain it in a similar manner to User Defaults.
open class KeychainWrapper: @unchecked Sendable {
    
    /// `serviceName` is used to uniquely identify this keychain accessor.
    let serviceName: String
    
    /// `accessGroup` is used to identify which Keychain Access Group this entry belongs to. This allows you to use shared keychain access between different applications.
    let accessGroup: String?
    
    init(serviceName: String, accessGroup: String? = nil) {
        self.serviceName = serviceName
        self.accessGroup = accessGroup
    }
    
    func get(forKey key: String,
             withAccessibility accessibility: KeychainAccessibility? = nil,
             isSynchronizable: Bool = false) throws -> Data? {
        var keychainQueryDictionary = query(forKey: key, withAccessibility: accessibility, isSynchronizable: isSynchronizable)
        keychainQueryDictionary[Self.matchLimit] = kSecMatchLimitOne
        keychainQueryDictionary[Self.returnData] = kCFBooleanTrue
        
        // Search
        var result: AnyObject?
        let status = SecItemCopyMatching(keychainQueryDictionary as CFDictionary, &result)
        
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return result as? Data
        default:
            throw KeychainWrapperError.status(status)
        }
    }
    
    func set(_ value: Data,
             forKey key: String,
             withAccessibility accessibility: KeychainAccessibility? = nil,
             isSynchronizable: Bool = false) throws {
        var keychainQueryDictionary = query(forKey: key, withAccessibility: accessibility, isSynchronizable: isSynchronizable)
        keychainQueryDictionary[Self.valueData] = value
        
        let status = SecItemAdd(keychainQueryDictionary as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try update(value, query: keychainQueryDictionary)
        } else if status != errSecSuccess {
            throw KeychainWrapperError.status(status)
        }
    }

    func remove(forKey key: String,
                withAccessibility accessibility: KeychainAccessibility? = nil,
                isSynchronizable: Bool = false) throws {
        let keychainQueryDictionary = query(forKey: key, withAccessibility: accessibility, isSynchronizable: isSynchronizable)
        
        let status = SecItemDelete(keychainQueryDictionary as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainWrapperError.status(status)
        }
    }
    
    func removeAll() throws {
        var keychainQueryDictionary: [String: Any] = [Self.class: kSecClassGenericPassword]
        keychainQueryDictionary[Self.attrService] = serviceName
        keychainQueryDictionary[Self.attrAccessGroup] = accessGroup
        
        let status = SecItemDelete(keychainQueryDictionary as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainWrapperError.status(status)
        }
    }
    
    // MARK: - Helpers
    
    private func update(_ value: Data, query: [String: Any]) throws {
        let updateDictionary = [Self.valueData: value]
        
        let status = SecItemUpdate(query as CFDictionary, updateDictionary as CFDictionary)
        if status != errSecSuccess {
            throw KeychainWrapperError.status(status)
        }
    }
    
    private func query(forKey key: String,
                       withAccessibility accessibility: KeychainAccessibility? = nil,
                       isSynchronizable: Bool = false) -> [String: Any] {
        var keychainQueryDictionary: [String: Any] = [Self.class: kSecClassGenericPassword]
        keychainQueryDictionary[Self.attrService] = serviceName
        keychainQueryDictionary[Self.attrAccessible] = accessibility?.key
        keychainQueryDictionary[Self.attrAccessGroup] = accessGroup
        keychainQueryDictionary[Self.useDataProtection] = kCFBooleanTrue
        keychainQueryDictionary[Self.attrAccount] = key
        keychainQueryDictionary[Self.attrSynchronizable] = isSynchronizable ? kCFBooleanTrue : kCFBooleanFalse
        return keychainQueryDictionary
    }
}

// MARK: - Keys

extension KeychainWrapper {
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
    private static let useDataProtection    = kSecUseDataProtectionKeychain as String

}

// MARK: - Accessibility

public enum KeychainAccessibility: Sendable {
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
