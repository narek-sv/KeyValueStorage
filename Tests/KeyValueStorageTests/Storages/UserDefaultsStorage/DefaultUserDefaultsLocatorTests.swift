//
//  DefaultUserDefaultsLocatorTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class DefaultUserDefaultsLocatorTests: XCTestCase {
    private let locator = DefaultUserDefaultsLocator()
    private let root = UserDefaultsStorage.Scope.app(.standard)

    // MARK: Suites

    func testEachScopesSuite() {
        XCTAssertEqual(locator.suite(for: .app(.standard)), .standard)
        XCTAssertEqual(locator.suite(for: .app(.suite(named: "suite"), namespace: .keyPrefix(named: "ns"))), .suite(named: "suite"))
        XCTAssertEqual(locator.suite(for: .appGroup(groupId: "group.test")), .suite(named: "group.test"))
    }

    // MARK: Stored Keys

    func testNamespacedKeysFollowTheEscapedNamespace() {
        let storedKeys = [
            ("ns", "key", "ns/key"),
            ("a/b", "c", "a%2Fb/c"),
            ("%", "c", "%25/c"),
            ("", "c", "/c"),
            ("ns", "a/b%", "ns/a/b%"),
            ("a/\u{301}", "c", "a%2F\u{301}/c")
        ]

        for (namespace, key, storedKey) in storedKeys {
            assertBytes(locator.storedKey(forKey: key, in: namespaced(namespace)), storedKey)
        }
    }

    func testAppGroupScopesPrefixTheirKeysLikeAppScopes() {
        assertBytes(locator.storedKey(forKey: "key", in: .appGroup(groupId: "group.test", namespace: .keyPrefix(named: "ns"))), "ns/key")
    }

    func testRootKeysEscapeOnlyPercentAndSlash() {
        // Pairs, not a dictionary: Swift's `==` takes `"\u{E9}"` and `"e\u{301}"` for one key
        let storedKeys = [("key", "key"), ("Key é 🙂", "Key é 🙂"), ("a/b", "a%2Fb"), ("100%", "100%25"), ("/\u{301}", "%2F\u{301}"), ("", "")]

        for (key, storedKey) in storedKeys {
            assertBytes(locator.storedKey(forKey: key, in: root), storedKey)
        }
    }

    // MARK: Keys

    func testStoredKeysNoKeyProducesArentClaimed() {
        for storedKey in ["a/b", "%41", "%2f", "%", "100%", "%2", "x%"] {
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
                storedName: { locator.storedKey(forKey: $0, in: scope) },
                key: { locator.key(forStoredKey: $0, in: scope) },
                sameName: { $0.utf8.elementsEqual($1.utf8) } // UserDefaults compares keys by their bytes
            )
        }
    }

    func testScopesNeverShareOrClaimEachOthersStoredKeys() {
        let scopes = [root] + ["", "a", "a/b", "a%2Fb", "%", "KeyValueStorage"].map(namespaced)
        let keys = ["", "b", "a/b", "b/c", "%", "%2F", "KeyValueStorage/key", "\u{301}x", "\u{E9}", "e\u{301}"]
        var owners = [[UInt8]: Int]()

        for (index, scope) in scopes.enumerated() {
            for key in keys {
                let storedKey = locator.storedKey(forKey: key, in: scope)
                XCTAssertNil(owners.updateValue(index, forKey: Array(storedKey.utf8)), "\(storedKey.debugDescription) is shared")

                for (other, otherScope) in scopes.enumerated() where other != index {
                    XCTAssertNil(locator.key(forStoredKey: storedKey, in: otherScope), "\(otherScope) claims \(storedKey.debugDescription)")
                }
            }
        }
    }

    // MARK: Helpers

    private func namespaced(_ name: String) -> UserDefaultsStorage.Scope {
        .app(.standard, namespace: .keyPrefix(named: name))
    }

    private func assertBytes(_ storedKey: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(storedKey.utf8.elementsEqual(expected.utf8), "\(storedKey.debugDescription) isn't \(expected.debugDescription)", file: file, line: line)
    }
}
