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

        // No reserved capacity: a byte can grow into three, so the key's length would be outgrown into a larger buffer
        var encoded = [UInt8]()
        for byte in utf8 {
            if Self.keptBytes.contains(byte) {
                encoded.append(byte)
            } else if Self.capitals.contains(byte) {
                encoded.append(UInt8(ascii: "!"))
                encoded.append(byte - Self.capitals.lowerBound + Self.lowercaseLetters.lowerBound)
            } else {
                encoded.append(UInt8(ascii: "%"))
                encoded.append(Self.lowercaseHexDigits[Int(byte >> 4)])
                encoded.append(Self.lowercaseHexDigits[Int(byte & 0x0F)])
            }
        }

        return String(decoding: encoded, as: UTF8.self)
    }

    /// Each `reserved` byte as `%XX`; include `%` to keep the result unambiguous.
    /// - Precondition: `reserved` holds only ASCII bytes: escaping part of a multi-byte character would corrupt it.
    func percentEscaping(_ reserved: Set<UInt8>) -> String {
        assert(reserved.allSatisfy { $0 < 0x80 }, "Only ASCII bytes can be escaped")
        // Bytes, because Foundation's `replacingOccurrences` skips a `/` that carries a combining mark
        var escaped = [UInt8]()
        // The result is at least as long as the key, so the buffer grows only for escapes
        escaped.reserveCapacity(utf8.count)
        for byte in utf8 {
            if reserved.contains(byte) {
                escaped.append(UInt8(ascii: "%"))
                escaped.append(Self.uppercaseHexDigits[Int(byte >> 4)])
                escaped.append(Self.uppercaseHexDigits[Int(byte & 0x0F)])
            } else {
                escaped.append(byte)
            }
        }

        return String(decoding: escaped, as: UTF8.self)
    }

    /// The exact inverse of `percentEscaping(reserved)`: `nil` for a name it never produces, such as one with a raw reserved
    /// byte, a lowercase or unreserved escape, or a cut-off one. So no two names decode to one, and every decoded name escapes back.
    /// - Precondition: `reserved` holds `%` and only ASCII bytes.
    init?(percentUnescaping name: String, _ reserved: Set<UInt8>) {
        assert(reserved.contains(UInt8(ascii: "%")) && reserved.allSatisfy { $0 < 0x80 }, "`%` and only ASCII bytes can be escaped")
        var bytes = [UInt8]()
        var rest = Substring(name).utf8
        while let byte = rest.popFirst() {
            if byte == UInt8(ascii: "%") {
                guard let high = rest.popFirst().flatMap(Self.uppercaseHexDigits.firstIndex),
                      let low = rest.popFirst().flatMap(Self.uppercaseHexDigits.firstIndex),
                      reserved.contains(UInt8(high << 4 | low)) else {
                    return nil
                }

                bytes.append(UInt8(high << 4 | low))
            } else if reserved.contains(byte) {
                return nil
            } else {
                bytes.append(byte)
            }
        }

        self = String(decoding: bytes, as: UTF8.self)
    }

    /// The rest after `prefix`, or `nil` without it.
    func droppingExactPrefix(_ prefix: String) -> String? {
        // Bytes, not characters: the rest can start with a combining mark, which joins the prefix's last character
        guard utf8.starts(with: prefix.utf8) else {
            return nil
        }

        return String(decoding: utf8.dropFirst(prefix.utf8.count), as: UTF8.self)
    }
}
