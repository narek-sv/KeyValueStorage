//
//  UserDefaultsStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - UserDefaultsStorage + Scope

public extension UserDefaultsStorage {
    /// Any string, even an empty one.
    typealias Namespace = ExactString

    /// - Note: Launch arguments and registered defaults under a stored key's name read as that key's value, in every suite.
    enum Scope: KeyValueDataStorageScope {
        /// The running app's or extension's own.
        /// - Note: A suite of the library's own, not `UserDefaults.standard`.
        /// - Warning: On macOS without App Sandbox, the user's other apps can read it.
        case own(namespace: Namespace)
        /// Shared by the apps and extensions in the App Group.
        /// - Warning: Without the App Group entitlement, values stay in this app, and nothing reports it.
        /// - Note: An empty id, the global domain's names (`NSGlobalDomain`, `.GlobalPreferences`, `kCFPreferencesAnyApplication`,
        ///   `Apple Global Domain`) and `.own`'s suite name throw `.invalidSuiteName`: every suite reads the global domain, and `.own`'s suite is `.own`'s alone.
        /// - Note: On macOS, ids that differ only in case share one suite.
        case appGroup(id: String, namespace: Namespace)

        public static var `default`: Self {
            .own(namespace: defaultNamespace)
        }
    }
}
