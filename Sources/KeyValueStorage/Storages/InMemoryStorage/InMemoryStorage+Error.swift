//
//  InMemoryStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - InMemoryStorage + Error

public extension InMemoryStorage {
    enum Error: KeyValueDataStorageError {
        case unknown
    }
}
