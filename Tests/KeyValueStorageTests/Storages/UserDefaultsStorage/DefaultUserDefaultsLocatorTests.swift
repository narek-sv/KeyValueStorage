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
    private let locator = FixedIdentifierUserDefaultsLocator()

    // MARK: Suites

    func testOwnScopesUseTheAppsSuiteAndGroupsTheirOwn() throws {
        XCTAssertEqual(try locator.suiteName(for: .own(namespace: "ns")), "com%2etest%2e!app.KeyValueStorage")
        XCTAssertEqual(try locator.suiteName(for: .appGroup(id: "group.test", namespace: "ns")), "group.test")
    }

    func testTheAppsSuiteIsItsIdentifierEncoded() throws {
        // Bundle IDs that differ only in case get two suite files, also on a volume that ignores case
        let names = try ["com.test.App", "com.test.app", "", "my tool"].map { identifier in
            locator.identifier = identifier
            return try locator.suiteName(for: .own(namespace: "ns"))
        }

        XCTAssertEqual(names, ["com%2etest%2e!app.KeyValueStorage", "com%2etest%2eapp.KeyValueStorage", "%.KeyValueStorage", "my%20tool.KeyValueStorage"])
    }

    func testGroupIdsThatAreTheGlobalDomainTheAppsSuiteOrEmptyThrow() {
        for groupId in ["", "NSGlobalDomain", ".GlobalPreferences", "kCFPreferencesAnyApplication", "Apple Global Domain", "com%2etest%2e!app.KeyValueStorage"] {
            assertThrows(UserDefaultsStorage.Error.invalidSuiteName(groupId)) {
                try locator.suiteName(for: .appGroup(id: groupId, namespace: "ns"))
            }
        }
    }

    // MARK: Stored Keys

    func testKeysFollowTheEscapedAndMarkedNamespace() {
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
            assertBytes(locator.storedKey(forKey: .init(key), in: .own(namespace: .init(namespace))), storedKey)
        }
    }

    func testAppGroupScopesStoreKeysLikeOwnScopes() {
        assertBytes(locator.storedKey(forKey: "key", in: .appGroup(id: "group.test", namespace: "ns")), "ns!/key")
    }

    // MARK: Keys

    func testStoredKeysNoKeyProducesArentClaimed() {
        // Other code's keys, such as `settings/theme`, never carry the mark
        for storedKey in ["ns", "ns/key", "ns!", "ns!key", "other!/key", "ns%2F!/key", "NS!/key", "settings/theme"] {
            XCTAssertNil(locator.key(forStoredKey: storedKey, in: .own(namespace: "ns")), storedKey.debugDescription)
        }
    }

    // MARK: Laws

    func testLawsWithinEachScope() {
        let keys = ["", "key", "Key", "a/b", "b/c", "!", "!/", "%", "%2F", "%25", "\u{301}x", "/\u{301}", "\u{E9}", "e\u{301}", "🙂"]

        for scope in [UserDefaultsStorage.Scope.own(namespace: "ns"), .own(namespace: ""), .appGroup(id: "group.test", namespace: "ns")] {
            assertLocatorLaws(
                keys: keys,
                foreignNames: ["ns/key", "settings/theme"],
                storedName: { locator.storedKey(forKey: .init($0), in: scope) },
                key: { locator.key(forStoredKey: $0, in: scope)?.string },
                sameName: { $0.utf8.elementsEqual($1.utf8) } // UserDefaults compares keys by their bytes
            )
        }
    }

    func testNamespacesNeverShareOrClaimEachOthersStoredKeys() {
        let scopes = ["", "a", "a!", "a!!", "a/b", "a%2Fb", "%", "!", "KeyValueStorage"].map { UserDefaultsStorage.Scope.own(namespace: .init($0)) }
        let keys = ["", "b", "!", "!/b", "a/b", "b/c", "%", "%2F", "KeyValueStorage!/key", "\u{301}x", "\u{E9}", "e\u{301}"]
        var owners = [[UInt8]: Int]()

        for (index, scope) in scopes.enumerated() {
            for key in keys {
                let storedKey = locator.storedKey(forKey: .init(key), in: scope)
                XCTAssertNil(owners.updateValue(index, forKey: Array(storedKey.utf8)), "\(storedKey.debugDescription) is shared")

                for (other, otherScope) in scopes.enumerated() where other != index {
                    XCTAssertNil(locator.key(forStoredKey: storedKey, in: otherScope), "\(otherScope) claims \(storedKey.debugDescription)")
                }
            }
        }
    }
}

/// The default locator with the app's identifier fixed.
/// Unchecked: used from one test at a time.
private final class FixedIdentifierUserDefaultsLocator: DefaultUserDefaultsLocator, @unchecked Sendable {
    var identifier = "com.test.App"

    override var ownIdentifier: String {
        identifier
    }
}
