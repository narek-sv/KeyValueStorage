//
//  ExactString.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 30.10.26.
//

import Foundation

// MARK: - ExactString

/// A string compared by its exact UTF-8 bytes; `String`'s `==` takes `"é"` and `"e\u{301}"` for one.
public struct ExactString: Hashable, Sendable, ExpressibleByStringInterpolation, CustomStringConvertible {
    public let string: String

    public var description: String {
        string
    }

    public init(_ string: String) {
        self.string = string
    }

    public init(stringLiteral string: String) {
        self.init(string)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        // In place when both strings hold their bytes together, as Swift's own always do and Foundation's ASCII ones do
        let inPlace = lhs.string.utf8.withContiguousStorageIfAvailable { lhsBytes in
            rhs.string.utf8.withContiguousStorageIfAvailable { rhsBytes in
                lhsBytes.count == rhsBytes.count && (lhsBytes.isEmpty || memcmp(lhsBytes.baseAddress!, rhsBytes.baseAddress!, lhsBytes.count) == 0)
            }
        }

        // Byte by byte otherwise, such as for a non-ASCII string bridged from Foundation, which has no UTF-8 bytes to share
        return (inPlace ?? nil) ?? lhs.string.utf8.elementsEqual(rhs.string.utf8)
    }

    public func hash(into hasher: inout Hasher) {
        // The bytes in one buffer: hashing runs on every dictionary lookup. In place when the string holds them together,
        // so a string bridged from Foundation isn't copied on every hash
        let hashedInPlace: Void? = string.utf8.withContiguousStorageIfAvailable { bytes in
            Self.combine(bytes, into: &hasher)
        }

        guard hashedInPlace == nil else {
            return
        }

        var string = string
        string.withUTF8 { bytes in
            Self.combine(bytes, into: &hasher)
        }
    }

    /// The count first, as `Array` does, so values hashing several strings don't collide on where one ends.
    private static func combine(_ bytes: UnsafeBufferPointer<UInt8>, into hasher: inout Hasher) {
        hasher.combine(bytes.count)
        hasher.combine(bytes: UnsafeRawBufferPointer(bytes))
    }
}
