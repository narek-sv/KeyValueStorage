//
//  KeychainBackingStore.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation
import Security

// MARK: - KeychainBackingStore

public protocol KeychainBackingStore {
    /// `SecItemCopyMatching`.
    func read(_ query: KeychainQuery) -> (KeychainOperationStatus, AnyObject?)
    /// `SecItemAdd`.
    func add(_ attributes: KeychainQuery) -> KeychainOperationStatus
    /// `SecItemUpdate`.
    func update(_ query: KeychainQuery, with attributes: KeychainQuery) -> KeychainOperationStatus
    /// `SecItemDelete`, which removes every item the query matches.
    func remove(_ query: KeychainQuery) -> KeychainOperationStatus
}

// MARK: - DefaultKeychainBackingStoreWrapper

/// The live keychain.
open class DefaultKeychainBackingStoreWrapper: KeychainBackingStore {
    public init() { }
    
    open func read(_ query: KeychainQuery) -> (KeychainOperationStatus, AnyObject?) {
        var result: AnyObject?
        let status = KeychainOperationStatus(status: SecItemCopyMatching(query.dictionary, &result))
        return (status, result)
    }
    
    open func add(_ attributes: KeychainQuery) -> KeychainOperationStatus {
        KeychainOperationStatus(status: SecItemAdd(attributes.dictionary, nil))
    }
    
    open func update(_ query: KeychainQuery, with attributes: KeychainQuery) -> KeychainOperationStatus {
        KeychainOperationStatus(status: SecItemUpdate(query.dictionary, attributes.dictionary))
    }
    
    open func remove(_ query: KeychainQuery) -> KeychainOperationStatus {
        KeychainOperationStatus(status: SecItemDelete(query.dictionary))
    }
}

// MARK: - KeychainQuery

public struct KeychainQuery: Sendable, Equatable {
    public let itemClass: ItemClass?
    public let service: String?
    public let account: String?
    public let accessGroup: String?
    public let synchronizable: Synchronizable?
    public let accessibility: Accessibility?
    public let useDataProtectionKeychain: Bool?
    public let returnData: Bool?
    public let matchLimit: MatchLimit?
    public let valueData: Data?
    
    public init(
        itemClass: ItemClass? = nil,
        service: String? = nil,
        account: String? = nil,
        accessGroup: String? = nil,
        synchronizable: Synchronizable? = nil,
        accessibility: Accessibility? = nil,
        useDataProtectionKeychain: Bool? = nil,
        returnData: Bool? = nil,
        matchLimit: MatchLimit? = nil,
        valueData: Data? = nil
    ) {
        self.itemClass = itemClass
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
        self.synchronizable = synchronizable
        self.accessibility = accessibility
        self.useDataProtectionKeychain = useDataProtectionKeychain
        self.returnData = returnData
        self.matchLimit = matchLimit
        self.valueData = valueData
    }
    
    var dictionary: CFDictionary {
        var dictionary = [String: Any]()
        dictionary[kSecClass as String] = itemClass?.value
        dictionary[kSecAttrService as String] = service
        dictionary[kSecAttrAccount as String] = account
        dictionary[kSecAttrAccessGroup as String] = accessGroup
        dictionary[kSecAttrSynchronizable as String] = synchronizable?.value
        dictionary[kSecAttrAccessible as String] = accessibility?.value
        dictionary[kSecUseDataProtectionKeychain as String] = useDataProtectionKeychain
        dictionary[kSecReturnData as String] = returnData
        dictionary[kSecMatchLimit as String] = matchLimit?.value
        dictionary[kSecValueData as String] = valueData
        return dictionary as CFDictionary
    }
}

// MARK: - KeychainQuery + Values

public extension KeychainQuery {
    enum ItemClass: Sendable {
        case genericPassword
        
        fileprivate var value: CFString {
            switch self {
            case .genericPassword:  return kSecClassGenericPassword
            }
        }
    }
    
    enum Synchronizable: Sendable {
        case yes
        case no
        
        fileprivate var value: CFBoolean {
            switch self {
            case .yes:  return kCFBooleanTrue
            case .no:   return kCFBooleanFalse
            }
        }
    }
    
    /// `kSecAttrAccessible`.
    enum Accessibility: Sendable {
        case afterFirstUnlock
        case afterFirstUnlockThisDeviceOnly
        case whenPasscodeSetThisDeviceOnly
        case whenUnlocked
        case whenUnlockedThisDeviceOnly
        
        fileprivate var value: CFString {
            switch self {
            case .afterFirstUnlock:                 return kSecAttrAccessibleAfterFirstUnlock
            case .afterFirstUnlockThisDeviceOnly:   return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            case .whenPasscodeSetThisDeviceOnly:    return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
            case .whenUnlocked:                     return kSecAttrAccessibleWhenUnlocked
            case .whenUnlockedThisDeviceOnly:       return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            }
        }
    }
    
    enum MatchLimit: Sendable {
        case one
        
        fileprivate var value: CFString {
            switch self {
            case .one:  return kSecMatchLimitOne
            }
        }
    }
}

// MARK: - KeychainOperationStatus

public enum KeychainOperationStatus: Equatable, Sendable {
    case success
    case notFound
    case duplicate
    case interactionNotAllowed
    case missingEntitlement
    case other(OSStatus)
    
    init(status: OSStatus) {
        switch status {
        case errSecSuccess:               self = .success
        case errSecItemNotFound:          self = .notFound
        case errSecDuplicateItem:         self = .duplicate
        case errSecInteractionNotAllowed: self = .interactionNotAllowed
        case errSecMissingEntitlement:    self = .missingEntitlement
        default:                          self = .other(status)
        }
    }
    
    var code: OSStatus {
        switch self {
        case .success:                return errSecSuccess
        case .notFound:               return errSecItemNotFound
        case .duplicate:              return errSecDuplicateItem
        case .interactionNotAllowed:  return errSecInteractionNotAllowed
        case .missingEntitlement:     return errSecMissingEntitlement
        case let .other(status):      return status
        }
    }
}
