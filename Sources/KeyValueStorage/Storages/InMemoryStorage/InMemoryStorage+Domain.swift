//
//  InMemoryStorage+Domain.swift
//  KeyValueStorage
//
//  Created by nsahakyan@servicetitan.com on 16.10.26.
//

import Foundation

// MARK: - InMemoryStorage + Domain

public extension InMemoryStorage {
    typealias Container = String

    enum Domain: KeyValueDataStorageDomain {
        case app(container: Container)

        public static var `default`: Self {
            .app(container: Self.defaultContainerName)
        }
    }
}
