//
//  UserDefaultsStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - UserDefaultsStorage + Error

public extension UserDefaultsStorage {
    enum Error: KeyValueDataStorageError {
        case failedToInitSharedDefaults
    }
}
