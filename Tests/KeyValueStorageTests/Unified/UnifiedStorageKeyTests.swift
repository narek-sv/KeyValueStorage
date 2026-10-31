//
//  UnifiedStorageKeyTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

/// `UnifiedStorage`'s cache and its observers tell keys apart by all four: the key, the scope, the value type and the storage type.
final class UnifiedStorageKeyTests: XCTestCase {
    func testEqualKeysAreEqualWithEqualHashes() {
        let key = FileKey<Int>(key: "key", scope: .own(namespace: "ns"))
        let same = FileKey<Int>(key: "key", scope: .own(namespace: "ns"))
        XCTAssertEqual(key, same)
        XCTAssertEqual(key.hashValue, same.hashValue)
    }

    func testTheDefaultScopeIsDefault() {
        XCTAssertEqual(FileKey<Int>(key: "key"), FileKey<Int>(key: "key", scope: .default))
    }

    func testEachPartTellsKeysApart() {
        let keys: Set<AnyHashable> = [
            FileKey<Int>(key: "key", scope: .own(namespace: "ns")),
            FileKey<Int>(key: "other", scope: .own(namespace: "ns")),
            FileKey<Int>(key: "key", scope: .own(namespace: "other")),
            FileKey<String>(key: "key", scope: .own(namespace: "ns")),
            UnifiedStorageKey<SQLiteStorage, Int>(key: "key", scope: .own(namespace: "ns"))
        ]

        XCTAssertEqual(keys.count, 5)
        XCTAssertNotEqual(FileKey<Int>(key: "\u{E9}"), FileKey<Int>(key: "e\u{301}"))
    }

    func testTheKeyKeepsItsParts() {
        let key = SQLiteKey<String>(key: "name", scope: .own(.cache, namespace: "ns"))
        XCTAssertEqual(key.key, "name")
        XCTAssertEqual(key.scope, .own(.cache, namespace: "ns"))
        XCTAssertTrue(key.codingType == String.self)
        XCTAssertTrue(key.storageType == SQLiteStorage.self)
    }
}
