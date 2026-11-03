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
    /// - Warning: So an entry whose protection changes, such as in an app update, finds none of the items saved with the old
    ///   one: move them with `UnifiedStorage.move(_:from:)`.
    enum Protection: Hashable, Sendable {
        /// Usable once the user has unlocked the device after a restart, then also while locked (`kSecAttrAccessibleAfterFirstUnlock`).
        case afterFirstUnlock
        /// As `afterFirstUnlock`, and never moves to another device (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
        case afterFirstUnlockThisDeviceOnly
        /// Usable only while the device is unlocked (`kSecAttrAccessibleWhenUnlocked`).
        /// - Warning: Background work can't use it while the device is locked.
        case whenUnlocked
        /// As `whenUnlocked`, and never moves to another device (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
        case whenUnlockedThisDeviceOnly
        /// As `whenUnlockedThisDeviceOnly`, and only while a passcode is set (`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`).
        /// - Warning: Saving fails without a passcode, and removing the passcode deletes the items.
        case whenPasscodeSetThisDeviceOnly
    }

    /// When the scope's items are usable; only the levels iCloud Keychain can sync.
    /// - Note: Part of the place: scopes that differ only in protection never share items.
    /// - Warning: So an entry whose protection changes, such as in an app update, finds none of the items saved with the old
    ///   one: move them with `UnifiedStorage.move(_:from:)`.
    enum SyncedProtection: Hashable, Sendable {
        /// Usable once the user has unlocked the device after a restart, then also while locked (`kSecAttrAccessibleAfterFirstUnlock`).
        case afterFirstUnlock
        /// Usable only while the device is unlocked (`kSecAttrAccessibleWhenUnlocked`).
        /// - Warning: Background work can't use it while the device is locked.
        case whenUnlocked
    }

    /// - Warning: Items outlive the app: deleting it leaves them in the keychain, and a reinstall finds them.
    enum Scope: DataStorageScope {
        /// The running app's or extension's own.
        /// - Warning: It belongs to the bundle ID: builds that share one share values, and unit tests hosted in the app use the
        ///   app's, so a test's `clear()` empties the app's data on that device. On macOS, `swift test` runs every package's
        ///   tests as `com.apple.dt.xctest.tool`, so they share one too. Give tests a namespace of their own.
        /// - Warning: Items go to the app's default access group, its first Keychain Sharing group if it lists any; apps sharing that group can read, change and delete them.
        case own(protection: Protection = .whenUnlocked, namespace: Namespace)
        /// Shared by the group's apps and extensions: an App Group, or a Keychain Sharing group with its team ID prefix.
        /// - Note: An empty id, or a group the app isn't entitled to, fails at the first call with `errSecMissingEntitlement`.
        case appGroup(id: String, protection: Protection = .whenUnlocked, namespace: Namespace)
        /// Synced to the user's other devices through iCloud Keychain; separate from the `.own` and `.appGroup` items of the same namespace.
        /// - Note: Items stay on this device while iCloud Keychain is off. With `.own`, only the app with the same bundle ID sees them on the other devices.
        case iCloud(Owner, protection: SyncedProtection = .whenUnlocked, namespace: Namespace)

        public static var `default`: Self {
            .own(namespace: defaultNamespace)
        }

        /// `own(protection:namespace:)`, with any string as the namespace, such as one made at runtime.
        public static func own(protection: Protection = .whenUnlocked, namespace: String) -> Self {
            .own(protection: protection, namespace: Namespace(namespace))
        }

        /// `appGroup(id:protection:namespace:)`, with any string as the namespace, such as one made at runtime.
        public static func appGroup(id: String, protection: Protection = .whenUnlocked, namespace: String) -> Self {
            .appGroup(id: id, protection: protection, namespace: Namespace(namespace))
        }

        /// `iCloud(_:protection:namespace:)`, with any string as the namespace, such as one made at runtime.
        public static func iCloud(_ owner: Owner, protection: SyncedProtection = .whenUnlocked, namespace: String) -> Self {
            .iCloud(owner, protection: protection, namespace: Namespace(namespace))
        }
    }
}
