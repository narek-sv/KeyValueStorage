//
//  KeychainStorage+Domain.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - KeychainStorage + Domain

public extension KeychainStorage {
    typealias Container = String

    enum Domain: KeyValueDataStorageDomain {
        case app(container: Container?)
        case appGroup(groupId: String, container: Container?)

        public static var `default`: Self {
            .app(container: Self.defaultContainerName)
        }
    }
}
