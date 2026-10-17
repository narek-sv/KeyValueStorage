//
//  KeychainBackingStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation
import Security

// MARK: - KeychainBackingStorage

/// `SecItem*` calls of `KeychainStorage`; statuses are returned, not thrown.
public protocol KeychainBackingStorage {
    /// `SecItemAdd`.
    func add(_ attributes: KeychainQuery) -> KeychainOperationStatus
    
    /// `SecItemCopyMatching`: the status and the result.
    func read(_ query: KeychainQuery) -> (KeychainOperationStatus, AnyObject?)
    
    /// `SecItemUpdate`; `attributes` holds item attributes only.
    func update(_ query: KeychainQuery, with attributes: KeychainQuery) -> KeychainOperationStatus
    
    /// `SecItemDelete`.
    func remove(_ query: KeychainQuery) -> KeychainOperationStatus
}

// MARK: - DefaultKeychainBackingStorage

/// The live `KeychainBackingStorage`.
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

/// A keychain query or item's attributes; only the set fields are sent.
public struct KeychainQuery: Sendable, Equatable {
    /// `kSecClass`
    public let itemClass: ItemClass?
    /// `kSecAttrService`
    public let service: String?
    /// `kSecAttrAccount`
    public let account: String?
    /// `kSecAttrAccessGroup`
    public let accessGroup: String?
    /// `kSecAttrSynchronizable`
    public let synchronizable: Synchronizable?
    /// `kSecAttrAccessible`
    public let accessibility: KeychainStorage.Key.Accessibility?
    /// `kSecUseDataProtectionKeychain`
    public let useDataProtectionKeychain: Bool?
    /// `kSecReturnData`
    public let returnData: Bool?
    /// `kSecMatchLimit`
    public let matchLimit: MatchLimit?
    /// `kSecValueData`
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
    
    /// The Security dictionary.
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
    /// `kSecClass` values.
    enum ItemClass: Sendable {
        case genericPassword
        
        internal var value: CFString {
            switch self {
            case .genericPassword:  return kSecClassGenericPassword
            }
        }
    }
    
    /// `kSecAttrSynchronizable` values; `any` is for searches only.
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
    
    /// `kSecMatchLimit` values.
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

/// A Security status, with cases for the common ones.
public enum KeychainOperationStatus: Equatable, Sendable {
    /// `errSecSuccess`
    case success
    /// `errSecItemNotFound`
    case notFound
    /// `errSecDuplicateItem`
    case duplicate
    /// `errSecInteractionNotAllowed`, e.g. while locked
    case interactionNotAllowed
    /// `errSecMissingEntitlement`
    case missingEntitlement
    /// Any other status
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
    
    /// The `OSStatus`.
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
