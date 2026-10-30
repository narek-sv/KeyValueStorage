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

    // MARK: init(portableName:)

    func testDecodingInvertsEncoding() {
        var everyASCIIByte = String(decoding: Array(UInt8(0)...0x7F), as: UTF8.self)
        everyASCIIByte += "\u{E9}"
        for sample in samples + [everyASCIIByte] {
            assertBytes(String(portableName: sample.portableName), sample)
        }
    }

    func testAPercentSignDecodesToTheEmptyName() {
        assertBytes(String(portableName: "%"), "")
    }

    func testNamesTheEncodingCantProduceDontDecode() {
        for name in ["a!", "!", "!A", "!1", "!!", "!%", "a%", "a%4", "%4", "%zz", "%g0", "%2E", "%%", "A", ".", " ", "a/b", "\u{E9}", "%25%"] {
            XCTAssertNil(String(portableName: name), name.debugDescription)
        }
    }

    func testNonCanonicalEscapesStillDecode() {
        // `DefaultFileLocator` re-encodes to reject these
        assertBytes(String(portableName: "%41"), "A")
        assertBytes(String(portableName: "%61"), "a")
        assertBytes(String(portableName: "%00"), "\0")
    }

    func testDecodingKeepsTheExactBytes() {
        assertBytes(String(portableName: "%c3%a9"), "\u{E9}")
        assertBytes(String(portableName: "e%cc%81"), "e\u{301}")
        XCTAssertNotEqual(ExactString(String(portableName: "%c3%a9")!), ExactString(String(portableName: "e%cc%81")!))
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
