//
//  FileStorage+Domain.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - FileStorage + Domain

public extension FileStorage {
    typealias Container = String

    enum AppDomain: KeyValueDataStorageContainer {
        case applicationSupport(container: Container)
        case cache(container: Container)
        case documents(container: Container)
        case temporary(container: Container)
    }

    enum Domain: KeyValueDataStorageDomain {
        case app(AppDomain)
        case appGroup(groupId: String, container: Container)

        public static var `default`: Self {
            .app(.applicationSupport(container: Self.defaultContainerName))
        }
    }
}
