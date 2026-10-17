//
//  UbiquitousStorage+Domain.swift
//  KeyValueStorage
//
//  Created by nsahakyan@servicetitan.com on 17.10.26.
//

// MARK: - UbiquitousStorage + Domain

@available(watchOS 9.0, *)
public extension UbiquitousStorage {
    typealias Container = String

    enum Domain: KeyValueDataStorageDomain {
        case shared(container: Container?)

        public static var `default`: Self {
            .shared(container: Self.defaultContainerName)
        }
    }
}
