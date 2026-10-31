//
//  KeychainStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - KeychainStorage + Scope

public extension KeychainStorage {
    /// Which apps see an iCloud scope's items.
    enum Owner: Hashable, Sendable {
        /// The running app or extension.
        /// - Warning: Items go to the app's default access group, its first Keychain Sharing group if it lists any; apps sharing that group can read, change and delete them.
        case own
        /// The group's apps and extensions: an App Group, or a Keychain Sharing group with its team ID prefix.
        /// - Note: An empty id, or a group the app isn't entitled to, fails at the first call with `errSecMissingEntitlement`.
        case appGroup(id: String)
    }

    /// When the scope's items are usable, and whether they may move to another device.
    /// - Note: Part of the place: scopes that differ only in protection never share items.
    enum Protection: Hashable, Sendable {
        /// Usable once the user has unlocked the device after a restart, then also while locked (`afterFirstUnlock`).
        case untilFirstUnlock
        /// As `untilFirstUnlock`, and never moves to another device (`afterFirstUnlockThisDeviceOnly`).
        case untilFirstUnlockThisDeviceOnly
        /// Usable only while the device is unlocked (`whenUnlocked`).
        /// - Warning: Background work can't use it while the device is locked.
        case whileLocked
        /// As `whileLocked`, and never moves to another device (`whenUnlockedThisDeviceOnly`).
        case whileLockedThisDeviceOnly
        /// As `whileLockedThisDeviceOnly`, and only while a passcode is set (`whenPasscodeSetThisDeviceOnly`).
        /// - Warning: Saving fails without a passcode, and removing the passcode deletes the items.
        case whileLockedOrWithoutPasscode
    }

    /// When the scope's items are usable; only the levels iCloud Keychain can sync.
    /// - Note: Part of the place: scopes that differ only in protection never share items.
    enum SyncedProtection: Hashable, Sendable {
        /// Usable once the user has unlocked the device after a restart, then also while locked (`afterFirstUnlock`).
        case untilFirstUnlock
        /// Usable only while the device is unlocked (`whenUnlocked`).
        /// - Warning: Background work can't use it while the device is locked.
        case whileLocked
    }

    /// - Warning: Items outlive the app: deleting it leaves them in the keychain, and a reinstall finds them.
    enum Scope: KeyValueDataStorageScope {
        /// The running app's or extension's own.
        /// - Warning: Items go to the app's default access group, its first Keychain Sharing group if it lists any; apps sharing that group can read, change and delete them.
        case own(protection: Protection = .whileLocked, namespace: Namespace)
        /// Shared by the group's apps and extensions: an App Group, or a Keychain Sharing group with its team ID prefix.
        /// - Note: An empty id, or a group the app isn't entitled to, fails at the first call with `errSecMissingEntitlement`.
        case appGroup(id: String, protection: Protection = .whileLocked, namespace: Namespace)
        /// Synced to the user's other devices through iCloud Keychain; separate from the `.own` and `.appGroup` items of the same namespace.
        /// - Note: Items stay on this device while iCloud Keychain is off. With `.own`, only the app with the same bundle ID sees them on the other devices.
        case iCloud(Owner, protection: SyncedProtection = .whileLocked, namespace: Namespace)

        public static var `default`: Self {
            .own(namespace: defaultNamespace)
        }
    }
}
