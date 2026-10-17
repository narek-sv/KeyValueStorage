//
//  SQLiteStorage+Domain.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - SQLiteStorage + Domain

public extension SQLiteStorage {
    /// A folder name; the database goes to `<container>/SQLite/KeyValueStorage.sqlite`.
    typealias Container = String

    /// The data protection class of the database and its `-wal` and `-shm` files, applied on every open.
    enum Protection: Sendable {
        /// The system default.
        case inherited
        /// Always accessible.
        case none
        /// Inaccessible while locked, even when open, so background work fails.
        case complete
        /// Inaccessible while locked, unless already open.
        case completeUnlessOpen
        /// Accessible after the first unlock.
        case completeUntilFirstUserAuthentication
    }

    /// A base directory in the app's sandbox, with a `<bundle id>` folder in it.
    enum AppDomain: KeyValueDataStorageContainer {
        /// `<Application Support>/<bundle id>/<container>/SQLite`: hidden, durable, backed up.
        case applicationSupport(container: Container)

        /// `<Caches>/<bundle id>/<container>/SQLite`: not backed up, may be purged.
        case cache(container: Container)

        /// `<Documents>/<bundle id>/<container>/SQLite`: backed up, may be visible to the user.
        case documents(container: Container)

        /// `<tmp>/<bundle id>/<container>/SQLite`: purged while the app isn't running.
        case temporary(container: Container)
    }

    /// Where the database is, and its protection.
    enum Domain: KeyValueDataStorageDomain {
        /// The app's own sandbox.
        case app(AppDomain, protection: Protection = .inherited)

        /// `<group container>/<container>/SQLite`, shared by the App Group; `groupId` as in the entitlement.
        /// Finish work before suspension: iOS kills apps that hold locks in group containers (`0xdead10cc`).
        case appGroup(groupId: String, container: Container, protection: Protection = .inherited)

        /// `.app(.applicationSupport(container: "KeyValueStorage"))`.
        public static var `default`: Self {
            .app(.applicationSupport(container: Self.defaultContainerName))
        }
    }
}
