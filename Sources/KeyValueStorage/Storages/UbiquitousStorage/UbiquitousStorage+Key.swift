//
//  UbiquitousStorage+Key.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

// MARK: - UbiquitousStorage + Key

@available(watchOS 9.0, *)
public extension UbiquitousStorage {
    /// A string of at most 128 UTF-16 code units, including the namespace prefix.
    typealias Key = String
}
