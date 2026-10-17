//
//  UserDefaultsStorage+Domain.swift
//  KeyValueStorage
//
//  Created by nsahakyan@servicetitan.com on 16.10.26.
//

import Foundation

// MARK: - UserDefaultsStorage + Domain

public extension UserDefaultsStorage {
    /// A suite name, or a key namespace in an App Group's suite.
    typealias Container = String

    /// A defaults domain in the app's sandbox.
    enum AppDomain: KeyValueDataStorageContainer {
        /// `UserDefaults.standard`; `clear()` removes everything the app saved there.
        case standard

        /// The suite `<bundle id>.<container>`.
        case suite(container: Container)
    }

    /// The suite that holds the values.
    enum Domain: KeyValueDataStorageDomain {
        /// The app's own defaults.
        case app(AppDomain)

        /// The suite `groupId`, with keys stored as `<container>/<key>`; shared by the App Group.
        case appGroup(groupId: String, container: Container)

        /// `.app(.suite(container: "KeyValueStorage"))`.
        public static var `default`: Self {
            .app(.suite(container: Self.defaultContainerName))
        }
    }
}
