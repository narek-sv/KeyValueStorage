//
//  FileStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - FileStorage + Scope

public extension FileStorage {
    /// Any string, even an empty one; `.invalidNamespace` if its encoded folder name exceeds 255 bytes.
    typealias Namespace = ExactString

    enum Retention: Hashable, Sendable {
        /// Kept until deleted.
        case persistent
        /// The system can delete it when storage runs low.
        case cache
        /// The system can delete it while the app isn't running.
        case temporary
    }

    /// Applies to every file the scope writes.
    /// - Note: Part of the place: scopes that differ only in protection never share values.
    enum Protection: Hashable, Sendable {
        /// No explicit class: the files get their folder's class or the app's default.
        case inherited
        /// Usable at any time, even before the first unlock after a restart (`none`).
        case none
        /// Usable once the user has unlocked the device after a restart, then also while locked (`completeUntilFirstUserAuthentication`).
        case untilFirstUnlock
        /// Usable only while the device is unlocked (`complete`).
        case whileLocked
        /// Saves work while locked; reads only while unlocked (`completeUnlessOpen`).
        case whileLockedUnlessOpen
    }

    enum Scope: KeyValueDataStorageScope {
        /// The running app's or extension's own.
        /// - Warning: On macOS without App Sandbox, the user's other apps can read it.
        case own(_ retention: Retention = .persistent, protection: Protection = .inherited, namespace: Namespace)
        /// Shared by the apps and extensions in the App Group.
        /// - Note: An empty id throws.
        /// - Note: On macOS, every id gets a folder, even one the app isn't entitled to, and ids that differ only in case share one.
        case appGroup(id: String, protection: Protection = .inherited, namespace: Namespace)

        public static var `default`: Self {
            .own(namespace: defaultNamespace)
        }
    }
}
