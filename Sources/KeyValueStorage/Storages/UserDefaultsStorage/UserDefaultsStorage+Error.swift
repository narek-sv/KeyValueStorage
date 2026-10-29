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
    }
}
