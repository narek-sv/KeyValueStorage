//
//  UbiquitousStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

// MARK: - UbiquitousStorage + Error

@available(watchOS 9.0, *)
public extension UbiquitousStorage {
    enum Error: KeyValueDataStorageError {
        /// With its namespace prefix, longer than 128 UTF-16 code units.
        case invalidKey(String)
        /// Over 1 MB, the store's limit per value.
        case valueTooLarge(key: String, size: Int)
    }
}
