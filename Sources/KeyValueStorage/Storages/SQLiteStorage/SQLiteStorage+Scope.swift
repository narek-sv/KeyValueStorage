//
//  SQLiteStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - SQLiteStorage + Scope

public extension SQLiteStorage {
    enum Retention: Hashable, Sendable {
        /// Kept until deleted, in Application Support, which the device's backups include: keep what you can download again
        /// in `.cache`.
        /// - Warning: On tvOS, an app's files must be purgeable: use `.cache` there.
        case persistent
        /// The system can delete it when storage runs low; it isn't backed up.
        case cache
        /// The system can delete it while the app isn't running; it isn't backed up.
        case temporary
    }

    /// Applies to the database and its `-wal` and `-shm` files.
    /// - Note: Part of the place: scopes that differ only in protection never share values.
    /// - Warning: So an entry whose protection changes, such as in an app update, finds none of the values saved with the old
    ///   one: move them with `UnifiedStorage.move(_:from:)`.
    enum Protection: Hashable, Sendable {
        /// No explicit class: the files get their folder's class or the app's default.
        case inherited
        /// Usable at any time, even before the first unlock after a restart (`none`).
        case none
        /// Usable once the user has unlocked the device after a restart, then also while locked (`completeUntilFirstUserAuthentication`).
        case afterFirstUnlock
        /// Usable only while the device is unlocked, even by an open database (`complete`).
        case whenUnlocked
        /// While locked, usable only by a storage created before locking, which keeps the database open (`completeUnlessOpen`).
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
        /// - Warning: iOS terminates an app that's suspended while it holds a lock on a file in a shared container
        ///   (`0xdead10cc`), and SQLite locks its database while it reads and writes: finish working with the scope before
        ///   the app is suspended, for example within a background task.
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

extension SQLiteStorage.Protection {
    var fileProtection: FileProtectionType? {
        switch self {
        case .inherited:             return nil
        case .none:                  return FileProtectionType.none
        case .afterFirstUnlock:      return .completeUntilFirstUserAuthentication
        case .whenUnlocked:          return .complete
        case .whenUnlockedOrOpen:    return .completeUnlessOpen
        }
    }
}
