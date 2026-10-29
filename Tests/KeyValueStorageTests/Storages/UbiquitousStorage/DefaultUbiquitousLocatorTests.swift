//
//  DefaultUbiquitousLocatorTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

@available(watchOS 9.0, *)
final class DefaultUbiquitousLocatorTests: XCTestCase {
    private let locator = DefaultUbiquitousLocator()
    private let root = UbiquitousStorage.Scope.shared()

    // MARK: Stored Keys

    func testNamespacedKeysFollowTheEscapedNamespace() throws {
        let storedKeys = [
            ("ns", "key", "ns/key"),
            ("a/b", "c", "a%2Fb/c"),
            ("%", "c", "%25/c"),
            ("", "c", "/c"),
            ("ns", "a/b%", "ns/a/b%"),
            ("a/\u{301}", "c", "a%2F\u{301}/c")
        ]

        for (namespace, key, storedKey) in storedKeys {
            assertBytes(try locator.storedKey(forKey: key, in: namespaced(namespace)), storedKey)
        }
    }

    func testRootKeysEscapeOnlyPercentAndSlash() throws {
        // Pairs, not a dictionary: Swift's `==` takes `"\u{E9}"` and `"e\u{301}"` for one key
        let storedKeys = [("key", "key"), ("Key é 🙂", "Key é 🙂"), ("a/b", "a%2Fb"), ("100%", "100%25"), ("/\u{301}", "%2F\u{301}"), ("", "")]

        for (key, storedKey) in storedKeys {
            assertBytes(try locator.storedKey(forKey: key, in: root), storedKey)
        }
    }

    func testStoredKeysOver128UTF16CodeUnitsThrow() throws {
        // Exactly 128 code units, then one more: the prefix and escapes count, and an emoji takes two
        let keys = [
            (root, String(repeating: "a", count: 128)),
            (namespaced("ns"), String(repeating: "a", count: 125)),
            (root, String(repeating: "/", count: 42) + "aa"),
            (root, String(repeating: "🙂", count: 64))
        ]

        for (scope, key) in keys {
            XCTAssertEqual(try locator.storedKey(forKey: key, in: scope).utf16.count, 128)
            assertThrows(UbiquitousStorage.Error.invalidKey(key + "a")) { try locator.storedKey(forKey: key + "a", in: scope) }
        }
    }

    // MARK: Keys

    func testStoredKeysNoKeyProducesArentClaimed() {
        for storedKey in ["a/b", "%41", "%2f", "%", "100%", "%2", "x%", String(repeating: "a", count: 129)] {
            XCTAssertNil(locator.key(forStoredKey: storedKey, in: root), storedKey.debugDescription)
        }

        for storedKey in ["ns", "other/key", "ns%2Fkey", "NS/key"] {
            XCTAssertNil(locator.key(forStoredKey: storedKey, in: namespaced("ns")), storedKey.debugDescription)
        }
    }

    // MARK: Laws

    func testLawsWithinEachScope() {
        let keys = ["", "key", "Key", "a/b", "b/c", "%", "%2F", "%25", "\u{301}x", "/\u{301}", "\u{E9}", "e\u{301}", "🙂"]

        for scope in [root, namespaced("ns"), namespaced("")] {
            assertLocatorLaws(
                keys: keys,
                foreignNames: ["%41", "a/b"].filter { _ in scope == root },
                storedName: { try locator.storedKey(forKey: $0, in: scope) },
                key: { locator.key(forStoredKey: $0, in: scope) },
                sameName: { $0.utf8.elementsEqual($1.utf8) } // the store compares keys by their bytes
            )
        }
    }

    func testScopesNeverShareOrClaimEachOthersStoredKeys() throws {
        let scopes = [root] + ["", "a", "a/b", "a%2Fb", "%", "KeyValueStorage"].map(namespaced)
        let keys = ["", "b", "a/b", "b/c", "%", "%2F", "KeyValueStorage/key", "\u{301}x", "\u{E9}", "e\u{301}"]
        var owners = [[UInt8]: Int]()

        for (index, scope) in scopes.enumerated() {
            for key in keys {
                let storedKey = try locator.storedKey(forKey: key, in: scope)
                XCTAssertNil(owners.updateValue(index, forKey: Array(storedKey.utf8)), "\(storedKey.debugDescription) is shared")

                for (other, otherScope) in scopes.enumerated() where other != index {
                    XCTAssertNil(locator.key(forStoredKey: storedKey, in: otherScope), "\(otherScope) claims \(storedKey.debugDescription)")
                }
            }
        }
    }

    // MARK: Helpers

    private func namespaced(_ name: String) -> UbiquitousStorage.Scope {
        .shared(namespace: .keyPrefix(named: name))
    }

    private func assertBytes(_ storedKey: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(storedKey.utf8.elementsEqual(expected.utf8), "\(storedKey.debugDescription) isn't \(expected.debugDescription)", file: file, line: line)
    }
}
