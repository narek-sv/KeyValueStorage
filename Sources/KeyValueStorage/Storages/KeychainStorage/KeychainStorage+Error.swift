//
//  KeychainStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - KeychainStorage + Error

public extension KeychainStorage {
    enum Error: Swift.Error, Sendable {
        /// A Security framework status, such as `errSecInteractionNotAllowed` while locked or `errSecMissingEntitlement`.
        case os(OSStatus)
    }
}

// MARK: - Internal

extension KeychainStorage.Error {
    /// For a status that failed the operation.
    init(_ status: KeychainOperationStatus) {
        self = .os(status.code)
    }
}
