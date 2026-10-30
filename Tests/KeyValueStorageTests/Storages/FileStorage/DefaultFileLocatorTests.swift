//
//  DefaultFileLocatorTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 28.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class DefaultFileLocatorTests: XCTestCase {
    private let locator = FixedDirectoriesFileLocator()
    private let scope = FileStorage.Scope.default

    // MARK: Directory

    func testOwnScopesUseTheirRetentionsBaseAndTheAppsFolder() throws {
        let bases: [(FileStorage.Retention, String)] = [(.persistent, "/support"), (.cache, "/caches"), (.temporary, "/temporary")]
        for (retention, path) in bases {
            XCTAssertEqual(try directory(.own(retention, namespace: "name")).path, path + "/com%2etest%2e!app/name!/i")
        }
    }

    func testAppGroupScopesUseTheGroupContainer() throws {
        XCTAssertEqual(try directory(.appGroup(id: "group.test", namespace: "name")).path, "/group/name!/i")
    }

    func testEachProtectionIsAFolderOfItsOwn() throws {
        let folders: [(FileStorage.Protection, String)] = [
            (.inherited, "i"), (.none, "n"), (.untilFirstUnlock, "u"), (.whileLocked, "w"), (.whileLockedUnlessOpen, "o")
        ]

        for (protection, folder) in folders {
            XCTAssertEqual(try directory(.own(protection: protection, namespace: "name")).lastPathComponent, folder)
            XCTAssertEqual(try directory(.appGroup(id: "group.test", protection: protection, namespace: "name")).lastPathComponent, folder)
        }
    }

    func testDefaultScopeUsesTheLibrarysNamespaceInApplicationSupport() throws {
        XCTAssertEqual(try directory(.default).path, "/support/com%2etest%2e!app/!key!value!storage!/i")
    }

    func testTheAppsFolderIsItsIdentifierEncodedLikeKeys() throws {
        // Bundle IDs that differ only in case get two folders, also on a volume that ignores case
        let folders = try ["com.test.App", "com.test.app", "", "my tool"].map { identifier in
            locator.identifier = identifier
            return try directory(.own(namespace: "name")).deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        }

        XCTAssertEqual(folders, ["com%2etest%2e!app", "com%2etest%2eapp", "%", "my%20tool"])
    }

    func testMissingBaseDirectoriesThrowTheirDirectory() {
        locator.directories = [:]

        assertThrows(FileStorage.Error.directoryNotFound(.applicationSupportDirectory)) {
            try directory(.own(namespace: "name"))
        }

        assertThrows(FileStorage.Error.directoryNotFound(.cachesDirectory)) {
            try directory(.own(.cache, namespace: "name"))
        }
    }

    func testAMissingGroupContainerOrAnEmptyIdThrowsTheId() {
        // macOS returns a container for any id, the empty one included
        locator.groupDirectories[""] = URL(fileURLWithPath: "/empty", isDirectory: true)

        assertThrows(FileStorage.Error.groupDirectoryNotFound("group.other")) {
            try directory(.appGroup(id: "group.other", namespace: "name"))
        }

        assertThrows(FileStorage.Error.groupDirectoryNotFound("")) {
            try directory(.appGroup(id: "", namespace: "name"))
        }
    }

    func testEveryScopeHasAFolderOfItsOwn() throws {
        let namespaces: [FileStorage.Namespace] = ["", "a", "A", "settings", "Settings", "a b", "a%20b", "\u{E9}", "e\u{301}"]
        let scopes = namespaces.flatMap { namespace -> [FileStorage.Scope] in
            [.own(namespace: namespace), .own(.cache, namespace: namespace), .own(protection: .whileLocked, namespace: namespace),
             .appGroup(id: "group.test", namespace: namespace)]
        }

        // Lowercased, as a volume that ignores case compares them
        let folders = try scopes.map { try directory($0).path.lowercased() }
        XCTAssertEqual(Set(folders).count, scopes.count)
    }

    // MARK: Namespaces

    func testNamespacesAreEncodedLikeKeysAndEndWithAnExclamationMark() throws {
        let folders = ["settings": "settings!", "KeyValueStorage": "!key!value!storage!", "": "%!", ".": "%2e!", "..": "%2e%2e!", "a/b": "a%2fb!"]
        for (name, folder) in folders {
            XCTAssertEqual(try directory(.own(namespace: .init(name))).deletingLastPathComponent().lastPathComponent, folder)
        }
    }

    func testNamespacesLongerThanAFolderNameThrow() throws {
        let longest = try directory(.own(namespace: .init(String(repeating: "a", count: 254))))
        XCTAssertEqual(longest.deletingLastPathComponent().lastPathComponent.utf8.count, 255)

        let name = FileStorage.Namespace(String(repeating: "a", count: 255))
        assertThrows(FileStorage.Error.invalidNamespace(name)) {
            try directory(.own(namespace: name))
        }
    }

    func testNamespaceIsCheckedBeforeTheEnvironment() {
        let name = FileStorage.Namespace(String(repeating: "A", count: 128))
        locator.directories = [:]

        assertThrows(FileStorage.Error.invalidNamespace(name)) {
            try directory(.own(namespace: name))
        }

        assertThrows(FileStorage.Error.invalidNamespace(name)) {
            try directory(.appGroup(id: "group.other", namespace: name))
        }
    }

    // MARK: File Names

    func testLowercaseLettersDigitsUnderscoresAndHyphensStay() throws {
        XCTAssertEqual(try fileName("abcxyz-0189_"), "abcxyz-0189_")
    }

    func testACapitalIsAnExclamationMarkAndItsLetter() throws {
        XCTAssertEqual(try fileName("KeyValueStorage"), "!key!value!storage")
        XCTAssertEqual(try fileName("AZ"), "!a!z")
    }

    func testEveryOtherByteIsAPercentSignAndTwoHexDigits() throws {
        // Pairs, not a dictionary: Swift's `==` takes `"\u{E9}"` and `"e\u{301}"` for one key
        let names = [
            (".", "%2e"), ("..", "%2e%2e"), (".hidden", "%2ehidden"), ("settings.json", "settings%2ejson"),
            (" ", "%20"), ("\t", "%09"), ("\n", "%0a"), ("/", "%2f"), ("\0", "%00"), ("!", "%21"), ("%", "%25"), ("~", "%7e"),
            ("\u{E9}", "%c3%a9"), ("e\u{301}", "e%cc%81"), ("🙂", "%f0%9f%99%82"), ("\u{FEFF}", "%ef%bb%bf")
        ]

        for (key, name) in names {
            XCTAssertEqual(try fileName(key), name, key.debugDescription)
        }
    }

    func testTheEmptyKeyIsAPercentSign() throws {
        XCTAssertEqual(try fileName(""), "%")
    }

    func testFileNamesOfMoreThan255BytesThrow() throws {
        XCTAssertEqual(try fileName(String(repeating: "a", count: 255)).utf8.count, 255)
        XCTAssertEqual(try fileName(String(repeating: "A", count: 127) + "a").utf8.count, 255)
        XCTAssertEqual(try fileName(String(repeating: "🙂", count: 21)).utf8.count, 252)

        for key in [String(repeating: "a", count: 256), String(repeating: "A", count: 128), String(repeating: "🙂", count: 22)] {
            assertThrows(FileStorage.Error.invalidKey(.init(key))) {
                try fileName(key)
            }
        }
    }

    // MARK: Keys

    func testNamesTheEncodingNeverWritesArentClaimed() {
        let foreign = [
            ".KeyValueStorage.sqlite", ".KeyValueStorage.sqlite-wal", ".DS_Store", "Notes", "a.b", "a b", "\u{E9}",
            "!", "!!", "a!", "!1", "!A", "%%", "%2", "%zz", "%2E", "%41", "%ff", "%c3", String(repeating: "a", count: 256)
        ]

        for name in foreign {
            XCTAssertNil(locator.key(forFileName: name, in: scope), name.debugDescription)
        }
    }

    func testSubclassesCanCallSuperForBothNameMethods() {
        // Given
        final class PrefixedLocator: DefaultFileLocator {
            override func fileName(forKey key: FileStorage.Key, in scope: FileStorage.Scope) throws(FileStorage.Error) -> String {
                try "v2-" + super.fileName(forKey: key, in: scope)
            }

            override func key(forFileName fileName: String, in scope: FileStorage.Scope) -> FileStorage.Key? {
                fileName.hasPrefix("v2-") ? super.key(forFileName: String(fileName.dropFirst(3)), in: scope) : nil
            }
        }

        let locator = PrefixedLocator()

        // When - Then
        assertLocatorLaws(
            keys: ["key", "Key", ".hidden", "%", ""],
            foreignNames: ["key", "v2-Key", "v2-%2E"],
            storedName: { try locator.fileName(forKey: .init($0), in: scope) },
            key: { locator.key(forFileName: $0, in: scope)?.string }
        )
    }

    // MARK: Laws

    func testLaws() {
        let ascii = (0..<128).map { String(UnicodeScalar(UInt8($0))) }
        let keys = ascii + [
            "", "key", "Key", "KEY", "kEy", "%", "%25", "!", "!a", "a/b", "a%2fb", "a b", "a.b",
            "\u{E9}", "e\u{301}", "\u{C5}", "\u{212B}", "\u{DF}", "ss", "\u{FB01}", "fi", "\u{131}", "\u{130}", "\u{212A}",
            "\u{FEFF}", "\u{FEFF}a", "\u{10410}\u{306}", "\u{4D0}", "\u{1110}\u{1176}", "\u{D30C}", // pairs Foundation's NFC merges
            "日本", "🙂", "👨‍👩‍👧", String(repeating: "a", count: 255)
        ]

        assertLocatorLaws(
            keys: keys,
            foreignNames: [".KeyValueStorage.sqlite", ".DS_Store", "Key", "%41", "%2E", "a.b"],
            storedName: { try locator.fileName(forKey: .init($0), in: scope) },
            key: { locator.key(forFileName: $0, in: scope)?.string },
            sameName: { $0.compare($1, options: .caseInsensitive) == .orderedSame } // APFS's default: case-insensitive, canonical
        )
    }

    // MARK: Helpers

    private func directory(_ scope: FileStorage.Scope) throws(FileStorage.Error) -> URL {
        try locator.directory(for: scope)
    }

    private func fileName(_ key: String) throws(FileStorage.Error) -> String {
        try locator.fileName(forKey: .init(key), in: scope)
    }
}
