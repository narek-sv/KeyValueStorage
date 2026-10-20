//
//  KeychainStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - KeychainStorage + Error

public extension KeychainStorage {
    /// The errors a `KeychainStorage` throws.
    enum Error: KeyValueDataStorageError {
        /// The keychain returned something other than `Data` for the item.
        case decodedWrongType
        /// A Security framework status, such as `errSecInteractionNotAllowed` while locked or `errSecMissingEntitlement`.
        case os(OSStatus)
    }
}
