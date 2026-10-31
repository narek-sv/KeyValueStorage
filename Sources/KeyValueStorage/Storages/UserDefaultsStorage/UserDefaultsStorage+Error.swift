//
//  UserDefaultsStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - UserDefaultsStorage + Error

public extension UserDefaultsStorage {
    /// The errors a `UserDefaultsStorage` throws.
    enum Error: Swift.Error, Sendable {
        /// The locator rejects it as a group id, or `UserDefaults` rejects it, such as the app's bundle identifier.
        case invalidSuiteName(String)
        /// A value that isn't `Data` is under this stored key; it's never replaced or removed.
        /// - Note: Registered defaults count, in every suite of the process.
        case keyOccupied(String)
    }
}
