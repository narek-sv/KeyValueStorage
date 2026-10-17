//
//  UbiquitousStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import Foundation

// MARK: - UbiquitousStorage + Error

@available(watchOS 9.0, *)
public extension UbiquitousStorage {
    enum Error: KeyValueDataStorageError {
        /// The prefixed key is over 128 UTF-16 units, which would make the store raise an exception.
        case invalidKey(String)

        /// The value is over 1 MB.
        case valueTooLarge(key: String, size: Int)
    }
}
