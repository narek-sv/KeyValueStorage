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

    func testAppScopesUseTheirBaseDirectory() throws {
        let custom = URL(fileURLWithPath: "/custom", isDirectory: true)
        let bases: [(FileStorage.AppScope, String)] = [
            (.applicationSupport, "/support"),
            (.cache, "/caches"),
            (.documents, "/documents"),
            (.temporary, "/temporary"),
            (.directory(at: custom), "/custom")
        ]

        for (appScope, path) in bases {
            XCTAssertEqual(try directory(.app(appScope)).path, path)
            XCTAssertEqual(try directory(.app(appScope, namespace: .directory(named: "name"))).path, path + "/name!")
        }
    }

    func testAppGroupScopesUseTheGroupContainer() throws {
        XCTAssertEqual(try directory(.appGroup(groupId: "group.test")).path, "/group")
        XCTAssertEqual(try directory(.appGroup(groupId: "group.test", namespace: .directory(named: "name"))).path, "/group/name!")
    }

    func testDefaultScopeUsesTheLibrarysFolderInApplicationSupport() throws {
        XCTAssertEqual(try directory(.default).path, "/support/!key!value!storage!")
    }

    func testMissingBaseDirectoriesThrowTheirDirectory() {
        locator.directories = [:]

        assertThrows(FileStorage.Error.directoryNotFound(.applicationSupportDirectory)) {
            try directory(.app(.applicationSupport))
        }

        assertThrows(FileStorage.Error.directoryNotFound(.cachesDirectory)) {
            try directory(.app(.cache))
        }

        assertThrows(FileStorage.Error.directoryNotFound(.documentDirectory)) {
            try directory(.app(.documents))
        }
    }

    func testMissingGroupContainerThrowsTheGroupId() {
        assertThrows(FileStorage.Error.groupDirectoryNotFound("group.other")) {
            try directory(.appGroup(groupId: "group.other"))
        }
    }

    func testDirectoryMustBeAFileURL() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/folder"))
        assertThrows(FileStorage.Error.invalidDirectory(url)) {
            try directory(.app(.directory(at: url)))
        }
    }

    // MARK: Namespaces

    func testNamespacesAreEncodedLikeKeysAndEndWithAnExclamationMark() throws {
        let folders = ["settings": "settings!", "KeyValueStorage": "!key!value!storage!", "": "%!", ".": "%2e!", "..": "%2e%2e!", "a/b": "a%2fb!"]
        for (name, folder) in folders {
            XCTAssertEqual(try directory(.app(.temporary, namespace: .directory(named: name))).lastPathComponent, folder)
        }
    }

    func testNamespacesLongerThanAFolderNameThrow() throws {
        XCTAssertEqual(try directory(.app(.temporary, namespace: .directory(named: String(repeating: "a", count: 254)))).lastPathComponent.utf8.count, 255)

        let name = String(repeating: "a", count: 255)
        assertThrows(FileStorage.Error.invalidNamespace(name)) {
            try directory(.app(.temporary, namespace: .directory(named: name)))
        }
    }

    func testNamespaceIsCheckedBeforeTheEnvironment() {
        let name = String(repeating: "A", count: 128)
        assertThrows(FileStorage.Error.invalidNamespace(name)) {
            try directory(.appGroup(groupId: "group.other", namespace: .directory(named: name)))
        }
    }

    func testNamespacesAndTheRootNeverShareAFolder() throws {
        let namespaces: [String?] = [nil, "", "a", "A", "settings", "Settings", "a b", "a%20b", "\u{E9}", "e\u{301}"]
        // Lowercased, as a case-insensitive volume compares them
        let folders = try namespaces.map { try directory(.app(.temporary, namespace: $0.map { .directory(named: $0) })).path.lowercased() }

        XCTAssertEqual(Set(folders).count, namespaces.count)
    }

    func testKeyFilesAndNamespaceFoldersNeverShareAName() throws {
        let names = (0..<128).map { String(UnicodeScalar(UInt8($0))) } + ["", "settings", "Settings", "a!", "%", "%21", "🙂"]
        let files = try Set(names.map(fileName))
        let folders = try Set(names.map { try directory(.app(.temporary, namespace: .directory(named: $0))).lastPathComponent })

        XCTAssertTrue(files.isDisjoint(with: folders))
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
            assertThrows(FileStorage.Error.invalidKey(key)) {
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
            override func fileName(forKey key: String, in scope: FileStorage.Scope) throws(FileStorage.Error) -> String {
                try "v2-" + super.fileName(forKey: key, in: scope)
            }

            override func key(forFileName fileName: String, in scope: FileStorage.Scope) -> String? {
                fileName.hasPrefix("v2-") ? super.key(forFileName: String(fileName.dropFirst(3)), in: scope) : nil
            }
        }

        let locator = PrefixedLocator()

        // When - Then
        assertLocatorLaws(
            keys: ["key", "Key", ".hidden", "%", ""],
            foreignNames: ["key", "v2-Key", "v2-%2E"],
            storedName: { try locator.fileName(forKey: $0, in: scope) },
            key: { locator.key(forFileName: $0, in: scope) }
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
            storedName: { try locator.fileName(forKey: $0, in: scope) },
            key: { locator.key(forFileName: $0, in: scope) },
            sameName: { $0.compare($1, options: .caseInsensitive) == .orderedSame } // APFS's default: case-insensitive, canonical
        )
    }

    // MARK: Helpers

    private func directory(_ scope: FileStorage.Scope) throws(FileStorage.Error) -> URL {
        try locator.directory(for: scope)
    }

    private func fileName(_ key: String) throws(FileStorage.Error) -> String {
        try locator.fileName(forKey: key, in: scope)
    }
}
