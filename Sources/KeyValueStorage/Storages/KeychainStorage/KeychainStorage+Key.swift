//
//  KeychainStorage+Key.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - KeychainStorage + Key

public extension KeychainStorage {
    struct Key: KeyValueDataStorageKey {
        public let name: String
        public let accessibility: Accessibility
        public let isSynchronizable: Bool
        
        public init(
            name: String,
            accessibility: Accessibility = .whenUnlocked,
            isSynchronizable: Bool = false
        ) {
            self.name = name
            self.accessibility = accessibility
            self.isSynchronizable = isSynchronizable
        }
    }
}

// MARK: - KeychainStorage.Key + Accessibility

public extension KeychainStorage.Key {
    enum Accessibility: Sendable {
        case afterFirstUnlock
        case afterFirstUnlockThisDeviceOnly
        case whenPasscodeSetThisDeviceOnly
        case whenUnlocked
        case whenUnlockedThisDeviceOnly
    }
}
