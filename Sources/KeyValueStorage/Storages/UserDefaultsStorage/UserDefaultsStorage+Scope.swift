//
//  UserDefaultsStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - UserDefaultsStorage + Scope

public extension UserDefaultsStorage {
    /// - Note: Launch arguments, the global domain and registered defaults under a stored key's name read as that key's
    ///   value, in every suite.
    enum Scope: DataStorageScope {
        /// The running app's or extension's own.
        /// - Warning: It belongs to the bundle ID: builds that share one share values, and unit tests hosted in the app use the
        ///   app's, so a test's `clear()` empties the app's data on that device. On macOS, `swift test` runs every package's
        ///   tests as `com.apple.dt.xctest.tool`, so they share one too. Give tests a namespace of their own.
        /// - Note: A suite of the library's own, not `UserDefaults.standard`.
        /// - Warning: On macOS without App Sandbox, the user's other apps can read it.
        case own(namespace: Namespace)
        /// Shared by the apps and extensions in the App Group.
        /// - Warning: Without the App Group entitlement, values stay in this app, and nothing reports it.
        /// - Note: An empty id, the global domain's names (`NSGlobalDomain`, `.GlobalPreferences`, `kCFPreferencesAnyApplication`,
        ///   `Apple Global Domain`) and `.own`'s suite name throw `.invalidSuiteName`: every suite reads the global domain, and `.own`'s suite is `.own`'s alone.
        /// - Warning: On macOS, ids that differ only in case write one file but read as two suites, so their values get lost or mixed.
        case appGroup(id: String, namespace: Namespace)

        public static var `default`: Self {
            .own(namespace: defaultNamespace)
        }

        /// `own(namespace:)`, with any string as the namespace, such as one made at runtime.
        public static func own(namespace: String) -> Self {
            .own(namespace: Namespace(namespace))
        }

        /// `appGroup(id:namespace:)`, with any string as the namespace, such as one made at runtime.
        public static func appGroup(id: String, namespace: String) -> Self {
            .appGroup(id: id, namespace: Namespace(namespace))
        }
    }
}
