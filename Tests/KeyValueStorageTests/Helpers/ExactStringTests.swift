//
//  ExactStringTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class ExactStringTests: XCTestCase {
    func testCanonicallyEquivalentStringsAreDistinct() {
        XCTAssertEqual("\u{E9}", "e\u{301}") // Swift's `String` takes them for one
        XCTAssertNotEqual(ExactString("\u{E9}"), ExactString("e\u{301}"))
        XCTAssertNotEqual(ExactString("\u{212B}"), ExactString("\u{C5}"))
    }

    func testSetsAndDictionariesKeepCanonicallyEquivalentStringsApart() {
        XCTAssertEqual(Set<ExactString>(["\u{E9}", "e\u{301}"]).count, 2)
        XCTAssertEqual(Set<String>(["\u{E9}", "e\u{301}"]).count, 1)

        var values = [ExactString: Int]()
        values["\u{E9}"] = 1
        values["e\u{301}"] = 2
        XCTAssertEqual(values["\u{E9}"], 1)
        XCTAssertEqual(values["e\u{301}"], 2)
    }

    func testEqualBytesAreEqualWithEqualHashes() {
        for string in ["", "a", "key", "\u{E9}", "e\u{301}", "🙂", String(repeating: "x", count: 1_000)] {
            let lhs = ExactString(string)
            let rhs = ExactString(String(decoding: Array(string.utf8), as: UTF8.self))
            XCTAssertEqual(lhs, rhs, string.debugDescription)
            XCTAssertEqual(lhs.hashValue, rhs.hashValue, string.debugDescription)
        }
    }

    func testDifferentBytesAreDifferent() {
        let strings = ["", "a", "A", "a ", " a", "ab", "ba", "\0", "\0\0", "\u{E9}", "e\u{301}", "🙂"]
        XCTAssertEqual(Set(strings.map { ExactString($0) }).count, strings.count)
    }

    func testHashesMarkWhereEachStringEnds() {
        struct Pair: Hashable {
            let first: ExactString
            let second: ExactString
        }

        func hash(_ first: ExactString, _ second: ExactString) -> Int {
            Pair(first: first, second: second).hashValue
        }

        XCTAssertNotEqual(hash("ab", "c"), hash("a", "bc"))
        XCTAssertNotEqual(hash("", "a"), hash("a", ""))
    }

    func testBridgedStringsHashLikeNativeOnes() {
        let bridged = NSString(string: "Caf\u{E9} 🙂") as String
        XCTAssertEqual(ExactString(bridged), ExactString("Caf\u{E9} 🙂"))
        XCTAssertEqual(ExactString(bridged).hashValue, ExactString("Caf\u{E9} 🙂").hashValue)
    }

    func testLiteralsInterpolationAndDescription() {
        let literal: ExactString = "key"
        let interpolated: ExactString = "k\("e")y"
        XCTAssertEqual(literal, ExactString("key"))
        XCTAssertEqual(interpolated, literal)
        XCTAssertEqual(literal.string, "key")
        XCTAssertEqual(literal.description, "key")
        XCTAssertEqual("\(literal)", "key")
    }
}
