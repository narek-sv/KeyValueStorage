//
//  UbiquitousStorage+Key.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

// MARK: - UbiquitousStorage + Key

@available(watchOS 9.0, *)
public extension UbiquitousStorage {
    /// Any string, even an empty one; `.invalidKey` if its stored key, namespace and escapes included, exceeds 128 UTF-16 code units.
    typealias Key = ExactString
}
