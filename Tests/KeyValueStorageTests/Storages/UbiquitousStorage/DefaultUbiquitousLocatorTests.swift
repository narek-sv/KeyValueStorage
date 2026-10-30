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

    // MARK: Stored Keys

    func testKeysFollowTheEscapedAndMarkedNamespace() throws {
        let storedKeys = [
            ("ns", "key", "ns!/key"),
            ("a/b", "c", "a%2Fb!/c"),
            ("%", "c", "%25!/c"),
            ("", "c", "!/c"),
            ("a!", "c", "a!!/c"),
            ("ns", "a/b%!", "ns!/a/b%!"),
            ("a/\u{301}", "c", "a%2F\u{301}!/c")
        ]

        for (namespace, key, storedKey) in storedKeys {
            assertBytes(try locator.storedKey(forKey: .init(key), in: scope(namespace)), storedKey)
        }
    }

    func testStoredKeysOver128UTF16CodeUnitsThrow() throws {
        // Exactly 128 code units, then one more: the namespace, its mark and escapes count, and an emoji takes two
        let keys = [
            ("ns", String(repeating: "a", count: 124)),
            ("", String(repeating: "a", count: 126)),
            (String(repeating: "/", count: 41), "aaa"),
            ("", String(repeating: "🙂", count: 63))
        ]

        for (namespace, key) in keys {
            XCTAssertEqual(try locator.storedKey(forKey: .init(key), in: scope(namespace)).utf16.count, 128)
            assertThrows(UbiquitousStorage.Error.invalidKey(.init(key + "a"))) { try locator.storedKey(forKey: .init(key + "a"), in: scope(namespace)) }
        }
    }

    // MARK: Keys

    func testStoredKeysNoKeyProducesArentClaimed() {
        // Other code's keys, such as `settings/theme`, never carry the mark
        for storedKey in ["ns", "ns/key", "ns!", "ns!key", "other!/key", "ns%2F!/key", "NS!/key", "settings/theme"] {
            XCTAssertNil(locator.key(forStoredKey: storedKey, in: scope("ns")), storedKey.debugDescription)
        }
    }

    // MARK: Laws

    func testLawsWithinEachScope() {
        let keys = ["", "key", "Key", "a/b", "b/c", "!", "!/", "%", "%2F", "%25", "\u{301}x", "/\u{301}", "\u{E9}", "e\u{301}", "🙂"]

        for scope in [scope("ns"), scope("")] {
            assertLocatorLaws(
                keys: keys,
                foreignNames: ["ns/key", "settings/theme"],
                storedName: { try locator.storedKey(forKey: .init($0), in: scope) },
                key: { locator.key(forStoredKey: $0, in: scope)?.string },
                sameName: { $0.utf8.elementsEqual($1.utf8) } // the store compares keys by their bytes
            )
        }
    }

    func testNamespacesNeverShareOrClaimEachOthersStoredKeys() throws {
        let scopes = ["", "a", "a!", "a!!", "a/b", "a%2Fb", "%", "!", "KeyValueStorage"].map(scope)
        let keys = ["", "b", "!", "!/b", "a/b", "b/c", "%", "%2F", "KeyValueStorage!/key", "\u{301}x", "\u{E9}", "e\u{301}"]
        var owners = [[UInt8]: Int]()

        for (index, scope) in scopes.enumerated() {
            for key in keys {
                let storedKey = try locator.storedKey(forKey: .init(key), in: scope)
                XCTAssertNil(owners.updateValue(index, forKey: Array(storedKey.utf8)), "\(storedKey.debugDescription) is shared")

                for (other, otherScope) in scopes.enumerated() where other != index {
                    XCTAssertNil(locator.key(forStoredKey: storedKey, in: otherScope), "\(otherScope) claims \(storedKey.debugDescription)")
                }
            }
        }
    }

    // MARK: Helpers

    private func scope(_ namespace: String) -> UbiquitousStorage.Scope {
        .iCloud(.own, namespace: .init(namespace))
    }

    private func assertBytes(_ storedKey: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(storedKey.utf8.elementsEqual(expected.utf8), "\(storedKey.debugDescription) isn't \(expected.debugDescription)", file: file, line: line)
    }
}
