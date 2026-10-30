//
//  UbiquitousStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

// MARK: - UbiquitousStorage + Error

@available(watchOS 9.0, *)
public extension UbiquitousStorage {
    enum Error: Swift.Error, Sendable {
        /// With its namespace, longer than 128 UTF-16 code units.
        case invalidKey(Key)
        /// Over 1 MB, the store's limit per value.
        case valueTooLarge(key: Key, size: Int)
        /// A value that isn't `Data` is under this stored key; it's never replaced or removed.
        case keyOccupied(String)
    }
}
