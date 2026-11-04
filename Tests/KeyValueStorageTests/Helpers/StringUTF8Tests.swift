//
//  StringUTF8Tests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class StringUTF8Tests: XCTestCase {
    private let keptBytes = Array("abcdefghijklmnopqrstuvwxyz0123456789_-".utf8)
    private let samples = [
        "", "a", "A", "%", "!", "/", ".", " ", "\0", "key", "KeyValueStorage", "com.Test.App", "%2F", "!a", "a!",
        "\u{E9}", "e\u{301}", "\u{301}", "\u{301}a", "/\u{301}", "🙂", "👨‍👩‍👧", "日本語", "\u{FFFF}", "\u{10FFFF}",
        String(repeating: "Ab%", count: 100)
    ]

    // MARK: portableName

    func testKeptBytesStay() {
        for byte in keptBytes {
            let name = String(decoding: [byte], as: UTF8.self)
            assertBytes(name.portableName, name)
        }

        assertBytes(String(decoding: keptBytes, as: UTF8.self).portableName, String(decoding: keptBytes, as: UTF8.self))
    }

    func testEveryCapitalIsAnExclamationMarkAndItsLowercaseLetter() {
        for capital in UInt8(ascii: "A")...UInt8(ascii: "Z") {
            let lowercase = capital + (UInt8(ascii: "a") - UInt8(ascii: "A"))
            assertBytes(String(decoding: [capital], as: UTF8.self).portableName, "!" + String(decoding: [lowercase], as: UTF8.self))
        }
    }

    func testEveryOtherByteIsAPercentSignAndTwoLowercaseHexDigits() {
        let capitals = UInt8(ascii: "A")...UInt8(ascii: "Z")
        for byte in UInt8(0)...0x7F where !keptBytes.contains(byte) && !capitals.contains(byte) {
            assertBytes(String(decoding: [byte], as: UTF8.self).portableName, String(format: "%%%02x", byte))
        }

        for (name, expected) in [("\0", "%00"), (".", "%2e"), ("!", "%21"), ("%", "%25"), ("/", "%2f"), (" ", "%20"), ("\u{7F}", "%7f")] {
            assertBytes(name.portableName, expected)
        }
    }

    func testMultiByteScalarsAreTheirUTF8Bytes() {
        assertBytes("\u{E9}".portableName, "%c3%a9")
        assertBytes("e\u{301}".portableName, "e%cc%81")
        assertBytes("🙂".portableName, "%f0%9f%99%82")
        assertBytes("Caf\u{E9}".portableName, "!caf%c3%a9")
    }

    func testLongNamesEncodeEveryByte() {
        let cases = [
            (String(repeating: "a", count: 10_000), String(repeating: "a", count: 10_000)),
            (String(repeating: "aB", count: 5_000), String(repeating: "a!b", count: 5_000)),
            (String(repeating: "/.", count: 5_000), String(repeating: "%2f%2e", count: 5_000)),
            (String(repeating: "a🙂", count: 2_500), String(repeating: "a%f0%9f%99%82", count: 2_500))
        ]
        for (name, expected) in cases {
            assertBytes(name.portableName, expected)
        }
    }

    func testTheEmptyNameIsAPercentSignAndDiffersFromAPercentSign() {
        assertBytes("".portableName, "%")
        assertBytes("%".portableName, "%25")
    }

    func testPortableNamesAreASCIIAndNeverStartWithADot() {
        let allowed = Set(keptBytes + Array("!%".utf8))
        for sample in samples {
            let name = sample.portableName
            XCTAssertTrue(name.utf8.allSatisfy(allowed.contains), sample.debugDescription)
            XCTAssertFalse(name.hasPrefix("."), sample.debugDescription)
        }
    }

    func testDistinctNamesGetDistinctPortableNames() {
        let names = samples.map { ExactString($0.portableName) }
        XCTAssertEqual(Set(names).count, Set(samples.map { ExactString($0) }).count)
    }

    func testIdentifiersEncodeAsTheLocatorsWrite() {
        assertBytes("com.test.App".portableName, "com%2etest%2e!app")
        assertBytes("my tool".portableName, "my%20tool")
        assertBytes("KeyValueStorage".portableName, "!key!value!storage")
    }

    // MARK: percentEscaping

    func testOnlyReservedBytesAreEscapedWithUppercaseHex() {
        let reserved: Set = [UInt8(ascii: "%"), UInt8(ascii: "/"), UInt8(ascii: ":")]
        assertBytes("%".percentEscaping(reserved), "%25")
        assertBytes("/".percentEscaping(reserved), "%2F")
        assertBytes(":".percentEscaping(reserved), "%3A")
        assertBytes("a%b/c:d".percentEscaping(reserved), "a%25b%2Fc%3Ad")
        assertBytes("com.test.App!_- ".percentEscaping(reserved), "com.test.App!_- ")
    }

    func testLongNamesEscapeEveryReservedByte() {
        // Escapes grow the result past the key's length
        let reserved: Set = [UInt8(ascii: "%"), UInt8(ascii: "/")]
        let cases = [
            (String(repeating: "a", count: 10_000), String(repeating: "a", count: 10_000)),
            (String(repeating: "/%", count: 5_000), String(repeating: "%2F%25", count: 5_000)),
            (String(repeating: "a/🙂", count: 2_500), String(repeating: "a%2F🙂", count: 2_500))
        ]
        for (name, expected) in cases {
            assertBytes(name.percentEscaping(reserved), expected)
        }
    }

    func testEveryByteCanBeReserved() {
        for byte in UInt8(0)...0x7F {
            assertBytes(String(decoding: [byte], as: UTF8.self).percentEscaping([byte]), String(format: "%%%02X", byte))
        }
    }

    func testEscapingThePercentSignKeepsEscapesUnambiguous() {
        let reserved: Set = [UInt8(ascii: "%"), UInt8(ascii: "/")]
        assertBytes("%2F".percentEscaping(reserved), "%252F")
        XCTAssertNotEqual(ExactString("%2F".percentEscaping(reserved)), ExactString("/".percentEscaping(reserved)))
    }

    func testASlashCarryingACombiningMarkIsEscaped() {
        assertBytes("/\u{301}".percentEscaping([UInt8(ascii: "/")]), "%2F\u{301}")
        assertBytes("a/\u{301}b".percentEscaping([UInt8(ascii: "/")]), "a%2F\u{301}b")
    }

    func testNothingReservedOrNothingToEscapeLeavesTheName() {
        for sample in samples {
            assertBytes(sample.percentEscaping([]), sample)
        }

        assertBytes("".percentEscaping([UInt8(ascii: "%")]), "")
    }

    func testNonASCIIBytesPassThrough() {
        let reserved: Set = [UInt8(ascii: "%"), UInt8(ascii: "/")]
        for sample in ["\u{E9}", "e\u{301}", "🙂", "日本語"] {
            assertBytes(sample.percentEscaping(reserved), sample)
        }
    }

    // MARK: init(percentUnescaping:)

    private let reserved: Set<UInt8> = Set([UInt8(ascii: "%"), UInt8(ascii: "/")] + Array(0x00...0x1F) + [0x7F])

    func testUnescapingInvertsEscaping() {
        let corpus = samples + ["%", "%%", "%2F", "a/b", "\0", "a\0b", "\u{1F}\u{7F}", "\n\t\r", String(decoding: Array(UInt8(0)...0x7F), as: UTF8.self)]
        for name in corpus {
            assertBytes(String(percentUnescaping: name.percentEscaping(reserved), reserved), name)
        }
    }

    func testOnlyNamesTheEscapingWritesAreUnescaped() {
        // Raw reserved bytes, lowercase, unreserved or cut-off escapes: escaping never writes them
        for name in ["%", "a%", "%2", "%2f", "%41", "%zz", "/", "a/b", "\0", "a\nb", "%25%", "%2G"] {
            XCTAssertNil(String(percentUnescaping: name, reserved), name.debugDescription)
        }
    }

    func testEveryUnescapedNameEscapesBack() {
        // So no two names unescape to one
        for name in ["", "a", "%25", "%2F", "%00", "a%2Fb%25", "\u{E9}%00e\u{301}", "🙂%1F"] {
            let unescaped = String(percentUnescaping: name, reserved)
            XCTAssertNotNil(unescaped, name.debugDescription)
            assertBytes(unescaped.map { $0.percentEscaping(reserved) }, name)
        }
    }

    func testNonASCIIPassesThroughUnescaping() {
        assertBytes(String(percentUnescaping: "\u{E9}e\u{301}🙂", reserved), "\u{E9}e\u{301}🙂")
    }

    // MARK: droppingExactPrefix

    func testAMatchingPrefixLeavesTheRest() {
        assertBytes("ns!/key".droppingExactPrefix("ns!/"), "key")
        assertBytes("ns!/".droppingExactPrefix("ns!/"), "")
        assertBytes("key".droppingExactPrefix(""), "key")
        assertBytes("".droppingExactPrefix(""), "")
    }

    func testAMissingPrefixIsNil() {
        XCTAssertNil("ns!/key".droppingExactPrefix("other!/"))
        XCTAssertNil("ns".droppingExactPrefix("ns!/"))
        XCTAssertNil("".droppingExactPrefix("a"))
        XCTAssertNil("Ns!/key".droppingExactPrefix("ns!/"))
    }

    func testPrefixesCompareByBytes() {
        // Swift's `hasPrefix` takes `"é"` for `"e\u{301}"` and refuses the `e` of `"e\u{301}"`
        XCTAssertNil("\u{E9}x".droppingExactPrefix("e"))
        XCTAssertNil("e\u{301}x".droppingExactPrefix("\u{E9}"))
        XCTAssertNil("\u{E9}x".droppingExactPrefix("e\u{301}"))
        assertBytes("e\u{301}x".droppingExactPrefix("e"), "\u{301}x")
        assertBytes("a!/\u{301}k".droppingExactPrefix("a!/"), "\u{301}k")
        assertBytes("🙂🙂".droppingExactPrefix("🙂"), "🙂")
    }

    func testDroppingInvertsPrepending() {
        for prefix in ["", "ns!/", "a%2F\u{301}!/", "\u{E9}"] {
            for sample in samples {
                assertBytes((prefix + sample).droppingExactPrefix(prefix), sample)
            }
        }
    }
}
