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
        /// `errSecInteractionNotAllowed`: the item is protected while the device is locked, or needs user interaction.
        case protectedDataUnavailable
        /// Any other Security framework status, such as `errSecMissingEntitlement` for a group the app isn't in.
        case keychain(status: OSStatus)
    }
}

// MARK: - Internal

extension KeychainStorage.Error {
    /// For a status that failed the operation.
    init(_ status: KeychainOperationStatus) {
        switch status {
        case .interactionNotAllowed:    self = .protectedDataUnavailable
        default:                        self = .keychain(status: status.code)
        }
    }
}
