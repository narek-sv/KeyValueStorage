//
//  FileStorage+Key.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - FileStorage + Key

public extension FileStorage {
    /// Any string, even an empty one; `.invalidKey` if its encoded file name exceeds 255 bytes.
    typealias Key = ExactString
}
