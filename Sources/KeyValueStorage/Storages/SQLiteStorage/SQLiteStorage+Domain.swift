//
//  SQLiteStorage+Domain.swift
//  KeyValueStorage
//
//  Created by nsahakyan@servicetitan.com on 16.10.26.
//

import Foundation

// MARK: - SQLiteStorage + Domain

public extension SQLiteStorage {
    typealias Container = String

    enum Protection: Sendable {
        case inherited
        case none
        case complete
        case completeUnlessOpen
        case completeUntilFirstUserAuthentication
    }

    enum AppDomain: KeyValueDataStorageContainer {
        case applicationSupport(container: Container)

        case cache(container: Container)

        case documents(container: Container)

        case temporary(container: Container)
    }

    enum Domain: KeyValueDataStorageDomain {
        case app(AppDomain, protection: Protection = .inherited)

        case appGroup(groupId: String, container: Container, protection: Protection = .inherited)

        public static var `default`: Self {
            .app(.applicationSupport(container: Self.defaultContainerName))
        }
    }
}
