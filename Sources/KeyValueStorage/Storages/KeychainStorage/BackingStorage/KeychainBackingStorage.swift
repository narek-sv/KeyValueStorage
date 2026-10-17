//
//  KeychainBackingStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation
import Security

// MARK: - KeychainBackingStorage

public protocol KeychainBackingStorage {
    func add(_ attributes: KeychainQuery) -> KeychainOperationStatus
    
    func read(_ query: KeychainQuery) -> (KeychainOperationStatus, AnyObject?)
    
    func update(_ query: KeychainQuery, with attributes: KeychainQuery) -> KeychainOperationStatus
    
    func remove(_ query: KeychainQuery) -> KeychainOperationStatus
}

// MARK: - DefaultKeychainBackingStorage

final class DefaultKeychainBackingStorage: KeychainBackingStorage {
    func add(_ query: KeychainQuery) -> KeychainOperationStatus {
        let query = query.dictionary
        return check(SecItemAdd(query as CFDictionary, nil))
    }
    
    func read(_ query: KeychainQuery) -> (KeychainOperationStatus, AnyObject?) {
        var result: AnyObject?
        let status = check(SecItemCopyMatching(query.dictionary as CFDictionary, &result))
        return (status, result)
    }
    
    func update(_ query: KeychainQuery, with attributes: KeychainQuery) -> KeychainOperationStatus {
        check(SecItemUpdate(query.dictionary as CFDictionary, attributes.dictionary as CFDictionary))
    }
    
    func remove(_ query: KeychainQuery) -> KeychainOperationStatus {
        check(SecItemDelete(query.dictionary as CFDictionary))
    }
    
    func check(_ status: OSStatus) -> KeychainOperationStatus {
        KeychainOperationStatus(status: status)
    }
}

// MARK: - KeychainQuery

public struct KeychainQuery: Sendable, Equatable {
    public let itemClass: ItemClass?
    public let service: String?
    public let account: String?
    public let accessGroup: String?
    public let synchronizable: Synchronizable?
    public let accessibility: KeychainStorage.Key.Accessibility?
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
        accessibility: KeychainStorage.Key.Accessibility? = nil,
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
    
    internal var dictionary: [String: Any] {
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
        return dictionary
    }
}

// MARK: - KeychainQuery + Values

public extension KeychainQuery {
    enum ItemClass: Sendable {
        case genericPassword
        
        internal var value: CFString {
            switch self {
            case .genericPassword:  return kSecClassGenericPassword
            }
        }
    }
    
    enum Synchronizable: Sendable {
        case yes
        case no
        case any
        
        internal var value: CFTypeRef {
            switch self {
            case .yes:  return kCFBooleanTrue
            case .no:   return kCFBooleanFalse
            case .any:  return kSecAttrSynchronizableAny
            }
        }
    }
    
    enum MatchLimit: Sendable {
        case one
        case all
        
        internal var value: CFString {
            switch self {
            case .one:  return kSecMatchLimitOne
            case .all:  return kSecMatchLimitAll
            }
        }
    }
}

extension KeychainStorage.Key.Accessibility {
    var value: CFString {
        switch self {
        case .afterFirstUnlock:                 return kSecAttrAccessibleAfterFirstUnlock
        case .afterFirstUnlockThisDeviceOnly:   return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenPasscodeSetThisDeviceOnly:    return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        case .whenUnlocked:                     return kSecAttrAccessibleWhenUnlocked
        case .whenUnlockedThisDeviceOnly:       return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
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
    case otherError(Int32)
    
    init(status: OSStatus) {
        switch status {
        case errSecSuccess:               self = .success
        case errSecItemNotFound:          self = .notFound
        case errSecDuplicateItem:         self = .duplicate
        case errSecInteractionNotAllowed: self = .interactionNotAllowed
        case errSecMissingEntitlement:    self = .missingEntitlement
        default:                          self = .otherError(status)
        }
    }
    
    var status: OSStatus {
        switch self {
        case .success:                return errSecSuccess
        case .notFound:               return errSecItemNotFound
        case .duplicate:              return errSecDuplicateItem
        case .interactionNotAllowed:  return errSecInteractionNotAllowed
        case .missingEntitlement:     return errSecMissingEntitlement
        case let .otherError(status): return OSStatus(status)
        }
    }
}
