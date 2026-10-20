//
//  UbiquitousStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

// MARK: - UbiquitousStorage + Error

@available(watchOS 9.0, *)
public extension UbiquitousStorage {
    /// The errors a `UbiquitousStorage` throws.
    enum Error: KeyValueDataStorageError {
        /// The key, with its namespace prefix, is longer than 128 UTF-16 code units.
        case invalidKey(String)
        /// The value is larger than 1 MB, the store's limit for one value.
        case valueTooLarge(key: String, size: Int)
    }
}
