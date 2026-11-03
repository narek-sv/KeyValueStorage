//
//  UnifiedStorageEntryTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

/// `UnifiedStorage`'s cache and its observers tell entries apart by all four: the key, the scope, the value type and the storage type.
final class UnifiedStorageEntryTests: XCTestCase {
    func testEqualEntriesAreEqualWithEqualHashes() {
        let entry = FileStorage.Entry<Int>(key: "key", scope: .own(namespace: "ns"))
        let same = FileStorage.Entry<Int>(key: "key", scope: .own(namespace: "ns"))
        XCTAssertEqual(entry, same)
        XCTAssertEqual(entry.hashValue, same.hashValue)
    }

    func testTheDefaultScopeIsDefault() {
        XCTAssertEqual(FileStorage.Entry<Int>(key: "key"), FileStorage.Entry<Int>(key: "key", scope: .default))
    }

    func testEachPartTellsEntriesApart() {
        let entries: Set<AnyHashable> = [
            FileStorage.Entry<Int>(key: "key", scope: .own(namespace: "ns")),
            FileStorage.Entry<Int>(key: "other", scope: .own(namespace: "ns")),
            FileStorage.Entry<Int>(key: "key", scope: .own(namespace: "other")),
            FileStorage.Entry<String>(key: "key", scope: .own(namespace: "ns")),
            SQLiteStorage.Entry<Int>(key: "key", scope: .own(namespace: "ns"))
        ]

        XCTAssertEqual(entries.count, 5)
        XCTAssertNotEqual(FileStorage.Entry<Int>(key: "\u{E9}"), FileStorage.Entry<Int>(key: "e\u{301}"))
    }

    func testAStringIsTheSameKeyAsALiteralOrAnExactString() {
        // Given: a name made at runtime
        let name = "key-\(42)"

        // When
        let entry = FileStorage.Entry<Int>(key: name, scope: .own(namespace: "ns"))
        let exact = FileStorage.Entry<Int>(key: ExactString(name), scope: .own(namespace: "ns"))

        // Then
        XCTAssertEqual(entry, exact)
        XCTAssertEqual(entry.hashValue, exact.hashValue)
        XCTAssertEqual(entry, FileStorage.Entry<Int>(key: "key-42", scope: .own(namespace: "ns")))
        XCTAssertEqual(entry.key, ExactString(name))
        XCTAssertEqual(FileStorage.Entry<Int>(key: name), FileStorage.Entry<Int>(key: ExactString(name), scope: .default))
    }

    func testAStringKeepsItsExactBytes() {
        let composed = "\u{E9}"
        let decomposed = "e\u{301}"
        XCTAssertNotEqual(FileStorage.Entry<Int>(key: composed), FileStorage.Entry<Int>(key: decomposed))
    }

    func testTheEntryKeepsItsParts() {
        let entry = SQLiteStorage.Entry<String>(key: "name", scope: .own(.cache, namespace: "ns"))
        XCTAssertEqual(entry.key, "name")
        XCTAssertEqual(entry.scope, .own(.cache, namespace: "ns"))
        XCTAssertTrue(entry.codingType == String.self)
        XCTAssertTrue(entry.storageType == SQLiteStorage.self)
    }
}
