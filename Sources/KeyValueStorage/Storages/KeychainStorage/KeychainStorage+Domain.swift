//
//  KeychainStorage+Domain.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - KeychainStorage + Domain

public extension KeychainStorage {
    /// The items' service, `kSecAttrService`.
    typealias Container = String

    /// The service and access group of the items, in the data protection keychain.
    enum Domain: KeyValueDataStorageDomain {
        /// Service `container` in the default access group; reads search every group. `nil` matches every service.
        case app(container: Container?)

        /// Service `container` in access group `groupId`: an App Group or a team-prefixed Keychain Sharing group.
        /// `nil` matches every service.
        case appGroup(groupId: String, container: Container?)

        /// `.app(container: "KeyValueStorage")`.
        public static var `default`: Self {
            .app(container: Self.defaultContainerName)
        }
    }
}
