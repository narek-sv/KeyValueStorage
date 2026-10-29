//
//  UserDefaultsStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - UserDefaultsStorage + Error

public extension UserDefaultsStorage {
    enum Error: KeyValueDataStorageError {
        /// `UserDefaults` rejects the app's bundle identifier and `NSGlobalDomain`.
        case invalidSuiteName(String)
        /// A value that isn't `Data` is under this stored key; it's never replaced or removed.
        /// - Note: Registered defaults count, in every suite of the process.
        case keyOccupied(String)
    }
}
