//
//  FileStorage+Domain.swift
//  KeyValueStorage
//
//  Created by nsahakyan@servicetitan.com on 16.10.26.
//

import Foundation

// MARK: - FileStorage + Domain

public extension FileStorage {
    /// A folder name; the files go to `<container>/Files`.
    typealias Container = String

    /// A base directory in the app's sandbox, with a `<bundle id>` folder in it.
    enum AppDomain: KeyValueDataStorageContainer {
        /// `<Application Support>/<bundle id>/<container>/Files`: hidden, durable, backed up.
        case applicationSupport(container: Container)

        /// `<Caches>/<bundle id>/<container>/Files`: not backed up, may be purged.
        case cache(container: Container)

        /// `<Documents>/<bundle id>/<container>/Files`: backed up, may be visible to the user.
        case documents(container: Container)

        /// `<tmp>/<bundle id>/<container>/Files`: purged while the app isn't running.
        case temporary(container: Container)
    }

    /// Where the files are.
    enum Domain: KeyValueDataStorageDomain {
        /// The app's own sandbox.
        case app(AppDomain)

        /// `<group container>/<container>/Files`, shared by the App Group; `groupId` as in the entitlement.
        case appGroup(groupId: String, container: Container)

        /// `.app(.applicationSupport(container: "KeyValueStorage"))`.
        public static var `default`: Self {
            .app(.applicationSupport(container: Self.defaultContainerName))
        }
    }
}
