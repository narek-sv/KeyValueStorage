//
//  KeychainStorage+Key.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - KeychainStorage + Key

public extension KeychainStorage {
    /// - Warning: A synchronizable item can't use a `ThisDeviceOnly` accessibility: saving it fails.
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

// MARK: - KeychainStorage.Key + ExpressibleByStringLiteral

extension KeychainStorage.Key: ExpressibleByStringLiteral {
    /// - Warning: The default, `.whenUnlocked`, can't be read while the device is locked, such as by background work.
    public init(stringLiteral name: String) {
        self.init(name: name)
    }
}

// MARK: - KeychainStorage.Key + Accessibility

public extension KeychainStorage.Key {
    enum Accessibility: Sendable {
        /// Once the user unlocks the device after a restart.
        case afterFirstUnlock
        /// Once the user unlocks the device after a restart; doesn't migrate to a new device.
        case afterFirstUnlockThisDeviceOnly
        /// While unlocked with a passcode set; doesn't migrate, and is deleted if the passcode is removed.
        case whenPasscodeSetThisDeviceOnly
        /// While unlocked (the default).
        case whenUnlocked
        /// While unlocked; doesn't migrate to a new device.
        case whenUnlockedThisDeviceOnly
    }
}
