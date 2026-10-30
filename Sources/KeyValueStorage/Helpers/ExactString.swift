//
//  ExactString.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 30.10.26.
//

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
        lhs.string.utf8.elementsEqual(rhs.string.utf8)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Array(string.utf8))
    }
}
