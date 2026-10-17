//
//  UserDefaultsStorage+Domain.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - UserDefaultsStorage + Domain

public extension UserDefaultsStorage {
    typealias Container = String

    enum AppDomain: KeyValueDataStorageContainer {
        case standard
        case suite(container: Container)
    }

    enum Domain: KeyValueDataStorageDomain {
        case app(AppDomain)
        case appGroup(groupId: String, container: Container)

        public static var `default`: Self {
            .app(.suite(container: Self.defaultContainerName))
        }
    }
}
