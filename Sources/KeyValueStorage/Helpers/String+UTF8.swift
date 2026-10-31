//
//  String+UTF8.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.10.26.
//

// MARK: - String

/// The default locators' name encodings, all on exact UTF-8 bytes: `"é"` and `"e\u{301}"` stay two names.
extension String {
    private static let keptBytes = Set("abcdefghijklmnopqrstuvwxyz0123456789_-".utf8)
    private static let capitals = UInt8(ascii: "A")...UInt8(ascii: "Z")
    private static let lowercaseLetters = UInt8(ascii: "a")...UInt8(ascii: "z")
    // Lowercase, so portable names hold no capitals; uppercase, as RFC 3986 recommends, for percent-escaping
    private static let lowercaseHexDigits = Array("0123456789abcdef".utf8)
    private static let uppercaseHexDigits = Array("0123456789ABCDEF".utf8)

    /// Lossless ASCII without capitals: `a`–`z`, `0`–`9`, `_` and `-` stay, a capital is `!` and its lowercase letter,
    /// any other byte is `%xx`, and the empty string is `%`.
    var portableName: String {
        guard !isEmpty else {
            return "%"
        }

        var encoded = [UInt8]()
        for byte in utf8 {
            if Self.keptBytes.contains(byte) {
                encoded.append(byte)
            } else if Self.capitals.contains(byte) {
                encoded += [UInt8(ascii: "!"), byte - Self.capitals.lowerBound + Self.lowercaseLetters.lowerBound]
            } else {
                encoded += Self.percentEncoded(byte, digits: Self.lowercaseHexDigits)
            }
        }

        return String(decoding: encoded, as: UTF8.self)
    }

    /// The inverse of `portableName`; `nil` for names it can't decode.
    /// - Note: Also decodes names the encoding never writes, such as `%41` for `A`.
    init?(portableName name: String) {
        guard name != "%" else {
            self = ""
            return
        }

        var bytes = [UInt8]()
        var rest = Substring(name).utf8
        while let byte = rest.popFirst() {
            if Self.keptBytes.contains(byte) {
                bytes.append(byte)
            } else if byte == UInt8(ascii: "!"), let letter = rest.popFirst(), Self.lowercaseLetters.contains(letter) {
                bytes.append(letter - Self.lowercaseLetters.lowerBound + Self.capitals.lowerBound)
            } else if byte == UInt8(ascii: "%"),
                      let high = rest.popFirst().flatMap(Self.lowercaseHexDigits.firstIndex),
                      let low = rest.popFirst().flatMap(Self.lowercaseHexDigits.firstIndex) {
                bytes.append(UInt8(high << 4 | low))
            } else {
                return nil
            }
        }

        self = String(decoding: bytes, as: UTF8.self)
    }

    /// Each `reserved` byte as `%XX`; include `%` to keep the result unambiguous.
    /// - Precondition: `reserved` holds only ASCII bytes: escaping part of a multi-byte character would corrupt it.
    func percentEscaping(_ reserved: Set<UInt8>) -> String {
        assert(reserved.allSatisfy { $0 < 0x80 }, "Only ASCII bytes can be escaped")
        // Bytes, because Foundation's `replacingOccurrences` skips a `/` that carries a combining mark
        var escaped = [UInt8]()
        for byte in utf8 {
            if reserved.contains(byte) {
                escaped += Self.percentEncoded(byte, digits: Self.uppercaseHexDigits)
            } else {
                escaped.append(byte)
            }
        }

        return String(decoding: escaped, as: UTF8.self)
    }

    /// The rest after `prefix`, or `nil` without it.
    func droppingExactPrefix(_ prefix: String) -> String? {
        // Bytes, not characters: the rest can start with a combining mark, which joins the prefix's last character
        guard utf8.starts(with: prefix.utf8) else {
            return nil
        }

        return String(decoding: utf8.dropFirst(prefix.utf8.count), as: UTF8.self)
    }

    private static func percentEncoded(_ byte: UInt8, digits: [UInt8]) -> [UInt8] {
        [UInt8(ascii: "%"), digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]]
    }
}
