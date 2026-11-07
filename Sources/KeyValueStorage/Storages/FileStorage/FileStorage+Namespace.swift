//
//  FileStorage+Namespace.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 30.10.26.
//

// MARK: - FileStorage + Namespace

public extension FileStorage {
    /// Any string, even an empty one; `.invalidNamespace` if its encoded folder name exceeds 255 bytes.
    typealias Namespace = ExactString
}
