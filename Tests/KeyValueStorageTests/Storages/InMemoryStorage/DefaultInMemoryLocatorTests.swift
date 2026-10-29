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

    func testTheBucketIsTheNamespacesName() {
        XCTAssertNil(locator.bucket(for: .app()))
        XCTAssertEqual(locator.bucket(for: .app(namespace: .bucket(named: ""))), "")
        XCTAssertEqual(locator.bucket(for: .default), "KeyValueStorage")
    }

    func testKeysAreStoredAsTheyAre() {
        for key in ["", "key", "Key", "a/b", "\u{E9}", "e\u{301}", "🙂"] {
            XCTAssertTrue(locator.storedKey(forKey: key, in: .default).utf8.elementsEqual(key.utf8), key.debugDescription)
        }
    }
}
