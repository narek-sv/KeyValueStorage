//
//  UbiquitousStorage+Key.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

// MARK: - UbiquitousStorage + Key

@available(watchOS 9.0, *)
public extension UbiquitousStorage {
    /// At most 128 UTF-16 code units, namespace prefix included.
    typealias Key = String
}
