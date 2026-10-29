//
//  KeychainStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - KeychainStorage + Error

public extension KeychainStorage {
    enum Error: KeyValueDataStorageError {
        /// An item whose data isn't `Data` is under this account; it's never replaced or removed.
        case keyOccupied(String)
        /// A Security framework status, such as `errSecInteractionNotAllowed` while locked or `errSecMissingEntitlement`.
        case os(OSStatus)
    }
}
