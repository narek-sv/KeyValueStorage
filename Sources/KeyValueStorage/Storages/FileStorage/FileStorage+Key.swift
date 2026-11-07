//
//  FileStorage+Key.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - FileStorage + Key

public extension FileStorage {
    /// Any string, even an empty one; `.invalidKey` if its encoded file name exceeds 255 bytes.
    /// - Note: A capital takes two bytes of the name, and any byte but `a`–`z`, `0`–`9`, `_` and `-` three, so a key in
    ///   Cyrillic fits about 42 characters and one in Chinese 28: hash longer keys, such as URLs with long query strings.
    typealias Key = ExactString
}
