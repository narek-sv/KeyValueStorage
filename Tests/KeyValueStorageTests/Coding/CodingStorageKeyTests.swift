//
//  CodingStorageKeyTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

/// The observation registry tells keys apart by these: the key and the value type.
final class CodingStorageKeyTests: XCTestCase {
    private typealias Key<Value: CodingValue> = CodingStorageKey<InMemoryStorage, Value>

    func testEqualKeysAndValueTypesAreEqualWithEqualHashes() {
        XCTAssertEqual(Key<Int>(key: "key"), Key<Int>(key: "key"))
        XCTAssertEqual(Key<Int>(key: "key").hashValue, Key<Int>(key: "key").hashValue)
    }

    func testAnotherKeyIsAnotherKey() {
        XCTAssertNotEqual(Key<Int>(key: "key"), Key<Int>(key: "other"))
        XCTAssertNotEqual(Key<Int>(key: "\u{E9}"), Key<Int>(key: "e\u{301}"))
    }

    func testAnotherValueTypeIsAnotherKey() {
        let keys: Set<AnyHashable> = [Key<Int>(key: "key"), Key<String>(key: "key"), Key<Int?>(key: "key")]
        XCTAssertEqual(keys.count, 3)
    }

    func testTheValueTypeIsKept() {
        XCTAssertTrue(Key<Int>(key: "key").codingType == Int.self)
        XCTAssertEqual(Key<Int>(key: "key").key, "key")
    }
}
