//
//  UserDefaultsStorage+Error.swift
//  KeyValueStorage
//
//  Created by nsahakyan@servicetitan.com on 16.10.26.
//

// MARK: - UserDefaultsStorage + Error

public extension UserDefaultsStorage {
    enum Error: KeyValueDataStorageError {
        case failedToInitSharedDefaults
    }
}
