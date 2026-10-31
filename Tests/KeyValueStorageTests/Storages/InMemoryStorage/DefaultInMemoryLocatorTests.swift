//
//  DefaultInMemoryLocatorTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class DefaultInMemoryLocatorTests: XCTestCase {
    private let locator = DefaultInMemoryLocator()

    func testTheBucketIsTheNamespacesExactBytes() {
        for namespace in ["", "name", "Name", "a/b", "\u{E9}", "e\u{301}", "🙂"] {
            XCTAssertTrue(locator.bucket(for: .own(namespace: .init(namespace))).utf8.elementsEqual(namespace.utf8), namespace.debugDescription)
        }

        XCTAssertEqual(locator.bucket(for: .default), "KeyValueStorage")
    }

    func testKeysAreStoredAsTheyAre() {
        for key in ["", "key", "Key", "a/b", "\u{E9}", "e\u{301}", "🙂"] {
            XCTAssertTrue(locator.storedKey(forKey: .init(key), in: .default).utf8.elementsEqual(key.utf8), key.debugDescription)
        }
    }
}
