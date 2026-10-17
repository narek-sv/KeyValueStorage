//
//  UbiquitousStorage+Domain.swift
//  KeyValueStorage
//
//  Created by nsahakyan@servicetitan.com on 17.10.26.
//

import Foundation

// MARK: - UbiquitousStorage + Domain

@available(watchOS 9.0, *)
public extension UbiquitousStorage {
    /// A key namespace in the store: keys are stored as `<container>/<key>`.
    typealias Container = String

    /// Keys in the store of the target's `com.apple.developer.ubiquity-kvstore-identifier` entitlement.
    /// Targets with the same identifier share it; extensions must set the app's identifier, or get their own store.
    enum Domain: KeyValueDataStorageDomain {
        /// The keys of `container`; `nil` uses raw keys, and `clear()` then wipes the store.
        case shared(container: Container?)

        /// `.shared(container: "KeyValueStorage")`.
        public static var `default`: Self {
            .shared(container: Self.defaultContainerName)
        }
    }
}
