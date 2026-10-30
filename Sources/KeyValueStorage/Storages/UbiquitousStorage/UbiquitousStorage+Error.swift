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
    enum Error: Swift.Error, Sendable {
        /// Its stored key, with the namespace, is over 128 UTF-16 code units.
        case invalidKey(Key)
        /// The value is over 1 MiB, the store's limit per value.
        case valueTooLarge(key: Key, size: Int)
        /// A value that isn't `Data` is under this stored key; it's never replaced or removed.
        case keyOccupied(String)
    }
}
