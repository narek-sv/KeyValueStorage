//
//  InMemoryStorage+Domain.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - InMemoryStorage + Domain

public extension InMemoryStorage {
    /// A container name in the backing storage.
    typealias Container = String

    /// The container that holds the values, in this process only.
    enum Domain: KeyValueDataStorageDomain {
        /// The values of `container`.
        case app(container: Container)

        /// `.app(container: "KeyValueStorage")`.
        public static var `default`: Self {
            .app(container: Self.defaultContainerName)
        }
    }
}
