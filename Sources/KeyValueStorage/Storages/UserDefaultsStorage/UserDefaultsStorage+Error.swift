//
//  UserDefaultsStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - UserDefaultsStorage + Error

public extension UserDefaultsStorage {
    /// The errors a `UserDefaultsStorage` throws.
    enum Error: KeyValueDataStorageError {
        /// `UserDefaults` rejected this suite name: the app's bundle identifier, or `NSGlobalDomain`.
        case invalidSuiteName(String)
    }
}
