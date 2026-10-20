//
//  KeychainStorage+Key.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - KeychainStorage + Key

public extension KeychainStorage {
    /// A generic password item whose account (`kSecAttrAccount`) is `name`.
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
    /// When the key's item can be read.
    enum Accessibility: Sendable {
        /// Once the user unlocks the device after a restart.
        case afterFirstUnlock
        /// Once the user unlocks the device after a restart; doesn't migrate to a new device.
        case afterFirstUnlockThisDeviceOnly
        /// While unlocked with a passcode set; doesn't migrate, and is deleted if the passcode is removed.
        case whenPasscodeSetThisDeviceOnly
        /// While the device is unlocked (the default).
        case whenUnlocked
        /// While the device is unlocked; doesn't migrate to a new device.
        case whenUnlockedThisDeviceOnly
    }
}
