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
        case invalidKey(String)
        case valueTooLarge(key: String, size: Int)
    }
}
