//
//  FileStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - FileStorage + Scope

public extension FileStorage {
    enum Retention: Hashable, Sendable {
        /// Kept until deleted, in Application Support, which the device's backups include: keep what you can download again
        /// in `.persistentExcludedFromBackup`, or in `.cache` if the system may delete it.
        /// - Warning: On tvOS, an app's files must be purgeable: use `.cache` there.
        case persistent
        /// Kept until deleted, in Application Support, but left out of the device's backups, so a restored or new device
        /// starts without it: for what you can download again but must keep, such as media for offline use.
        /// - Note: The system takes the exclusion as guidance, not as a guarantee.
        /// - Warning: On tvOS, an app's files must be purgeable: use `.cache` there.
        case persistentExcludedFromBackup
        /// The system can delete it when storage runs low; it isn't backed up.
        case cache
        /// The system can delete it while the app isn't running; it isn't backed up.
        case temporary
    }

    /// Applies to every file the scope writes.
    /// - Note: Part of the place: scopes that differ only in protection never share values.
    /// - Warning: So an entry whose protection changes, such as in an app update, finds none of the values saved with the old
    ///   one: move them with `UnifiedStorage.move(_:to:)`.
    enum Protection: Hashable, Sendable {
        /// No explicit class: the files get their folder's class or the app's default.
        case inherited
        /// Usable at any time, even before the first unlock after a restart (`none`).
        case none
        /// Usable once the user has unlocked the device after a restart, then also while locked (`completeUntilFirstUserAuthentication`).
        case afterFirstUnlock
        /// Usable only while the device is unlocked (`complete`).
        case whenUnlocked
        /// Saves work while locked; reads only while unlocked (`completeUnlessOpen`).
        case whenUnlockedOrOpen
    }

    enum Scope: DataStorageScope {
        /// The running app's or extension's own.
        /// - Warning: It belongs to the bundle ID: builds that share one share values, and unit tests hosted in the app use the
        ///   app's, so a test's `clear()` empties the app's data on that device. On macOS, `swift test` runs every package's
        ///   tests as `com.apple.dt.xctest.tool`, so they share one too. Give tests a namespace of their own.
        /// - Warning: On macOS without App Sandbox, the user's other apps can read it.
        case own(_ retention: Retention = .persistent, protection: Protection = .inherited, namespace: Namespace)
        /// Shared by the apps and extensions in the App Group.
        /// - Note: An empty id throws.
        /// - Note: On macOS and in the Simulator, every id gets a folder, even one the app isn't entitled to. On macOS, ids that
        ///   differ only in case share one.
        case appGroup(id: String, protection: Protection = .inherited, namespace: Namespace)

        public static var `default`: Self {
            .own(namespace: defaultNamespace)
        }

        /// `own(_:protection:namespace:)`, with any string as the namespace, such as one made at runtime.
        public static func own(_ retention: Retention = .persistent, protection: Protection = .inherited, namespace: String) -> Self {
            .own(retention, protection: protection, namespace: Namespace(namespace))
        }

        /// `appGroup(id:protection:namespace:)`, with any string as the namespace, such as one made at runtime.
        public static func appGroup(id: String, protection: Protection = .inherited, namespace: String) -> Self {
            .appGroup(id: id, protection: protection, namespace: Namespace(namespace))
        }
    }
}

// MARK: - Internal

extension FileStorage.Protection {
    @available(macOS 11, *)
    var fileProtection: Data.WritingOptions? {
        switch self {
        case .inherited:             return nil
        case .none:                  return .noFileProtection
        case .afterFirstUnlock:      return .completeFileProtectionUntilFirstUserAuthentication
        case .whenUnlocked:          return .completeFileProtection
        case .whenUnlockedOrOpen:    return .completeFileProtectionUnlessOpen
        }
    }
}
