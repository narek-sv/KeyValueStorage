//
//  FileStorageTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.12.23.
//

import XCTest
import Foundation
@testable import KeyValueStorage

/// The storage's rules against an in-memory file system; the real one is in `FileIntegrationTests`.
final class FileStorageTests: XCTestCase {
    private typealias Items = [String: FileBackingStoreMock.Item]

    private let root = URL(fileURLWithPath: "/root", isDirectory: true)
    private let data = Data([0xAA, 0xBB])
    private let backingStore = FileBackingStoreMock()

    private var scope: FileStorage.Scope {
        .app(.directory(at: root))
    }

    /// Every way a key can have no value: no folder, no file, a folder or a link at the file's path,
    /// or a file or a link where the folder goes.
    private var noValue: [Items] {
        [
            [:],
            [root.path: .directory],
            [root.path: .directory, path("key"): .directory, path("key/inner"): .file(data)],
            [root.path: .directory, path("key"): .link],
            [root.path: .file(data)],
            [root.path: .link]
        ]
    }

    // MARK: Initializers

    func testInitResolvesTheFolderWithoutFileSystemCalls() throws {
        // When
        let storage = try FileStorage(scope: .app(.temporary, namespace: .directory(named: "name")), backingStore: backingStore, locator: FixedDirectoriesFileLocator())

        // Then
        XCTAssertEqual(backingStore.calls, [])
        try storage.save(data, forKey: "key")
        XCTAssertEqual(backingStore.items["/temporary/name!/key"], .file(data))
    }

    func testInitThrowsTheLocatorsError() {
        // Given
        let locator = FileLocatorStub()
        locator.directoryError = .groupDirectoryNotFound("group.other")

        // When - Then
        assertThrows(FileStorage.Error.groupDirectoryNotFound("group.other")) {
            try FileStorage(scope: scope, backingStore: backingStore, locator: locator)
        }

        XCTAssertEqual(backingStore.calls, [])
    }

    func testScopeIsTheOneGiven() throws {
        XCTAssertEqual(try makeStorage().scope, scope)
    }

    // MARK: Locator

    func testStorageUsesExactlyTheLocatorsNames() throws {
        // Given
        let locator = FileLocatorStub()
        locator.keys = ["located-key": "key"]
        let storage = try FileStorage(scope: scope, backingStore: backingStore, locator: locator)
        let folder = locator.directory.path
        let file = locator.directory.appendingPathComponent("located-key").path
        let other = locator.directory.appendingPathComponent("other").path

        // When - Then
        try storage.save(data, forKey: .init(name: "key", protection: .complete))
        XCTAssertEqual(backingStore.items, [folder: .directory, file: .file(data)])
        XCTAssertEqual(try storage.fetch(forKey: "key"), data)
        try storage.delete(forKey: "key")
        XCTAssertEqual(backingStore.items, [folder: .directory])

        try storage.save(data, forKey: "key")
        backingStore.items[other] = .file(data)
        try storage.clear()
        XCTAssertEqual(backingStore.items, [folder: .directory, other: .file(data)])

        XCTAssertEqual(locator.calls, [
            .directory(scope),
            .fileName("key", scope),
            .fileName("key", scope),
            .fileName("key", scope),
            .fileName("key", scope),
            .key("located-key", scope),
            .fileName("key", scope),
            .key("other", scope)
        ])
    }

    func testLocatorErrorsStopBeforeTheFileSystem() throws {
        // Given
        let locator = FileLocatorStub()
        locator.fileNameError = .invalidKey("key")
        let storage = try FileStorage(scope: scope, backingStore: backingStore, locator: locator)
        let expected = FileStorage.Error.invalidKey("key")

        // When - Then
        assertThrows(expected) { try storage.fetch(forKey: "key") }
        assertThrows(expected) { try storage.save(data, forKey: "key") }
        assertThrows(expected) { try storage.delete(forKey: "key") }
        XCTAssertEqual(backingStore.calls, [])
    }

    func testInvalidKeysStopBeforeTheFileSystem() throws {
        // Given
        let storage = try makeStorage()
        let key = String(repeating: "a", count: 256)
        let expected = FileStorage.Error.invalidKey(key)

        // When - Then
        assertThrows(expected) { try storage.fetch(forKey: .init(name: key)) }
        assertThrows(expected) { try storage.save(data, forKey: .init(name: key)) }
        assertThrows(expected) { try storage.delete(forKey: .init(name: key)) }
        XCTAssertEqual(backingStore.calls, [])
    }

    // MARK: Files Are Values, Folders Are Namespaces

    func testFetchReadsTheKeysFile() throws {
        // Given
        backingStore.items = [root.path: .directory, path("!key"): .file(data)]

        // When - Then
        XCTAssertEqual(try makeStorage().fetch(forKey: "Key"), data)
    }

    func testWithoutAFileInTheFolderThereIsNoValue() throws {
        for items in noValue {
            // Given
            let backingStore = FileBackingStoreMock()
            backingStore.items = items
            let storage = try makeStorage(backingStore)

            // When
            let fetched = try storage.fetch(forKey: "key")
            try storage.delete(forKey: "key")

            // Then: nothing is read, and nothing changes
            XCTAssertNil(fetched, "\(items)")
            XCTAssertEqual(backingStore.items, items)
            XCTAssertFalse(backingStore.calls.contains(.read(file("key"))), "\(items)")
            XCTAssertFalse(backingStore.calls.contains(.remove(file("key"))), "\(items)")
        }
    }

    func testFetchNeverLooksIntoAValueWhereTheFolderGoes() throws {
        // Given
        backingStore.items = [root.path: .file(data)]

        // When
        _ = try makeStorage().fetch(forKey: "key")

        // Then
        XCTAssertEqual(backingStore.calls, [.itemType(root)])
    }

    // MARK: Save

    func testSaveWritesAtomicallyWithTheKeysProtection() throws {
        // Given
        let storage = try makeStorage()
        let options: [(FileStorage.Key.Protection, Data.WritingOptions)] = [
            (.inherited, .atomic),
            (.none, [.atomic, .noFileProtection]),
            (.complete, [.atomic, .completeFileProtection]),
            (.completeUnlessOpen, [.atomic, .completeFileProtectionUnlessOpen]),
            (.completeUntilFirstUserAuthentication, [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        ]

        // When
        for (protection, _) in options {
            try storage.save(data, forKey: .init(name: "key", protection: protection))
        }

        // Then
        let written = backingStore.calls.compactMap { call -> Data.WritingOptions? in
            guard case let .write(_, _, options) = call else {
                return nil
            }

            return options
        }

        XCTAssertEqual(written, options.map(\.1))
    }

    func testSaveCreatesTheFolderAndReplacesTheFile() throws {
        // Given
        let storage = try makeStorage()

        // When - Then
        try storage.save(Data([1]), forKey: "key")
        XCTAssertEqual(backingStore.items, [root.path: .directory, path("key"): .file(Data([1]))])
        try storage.save(data, forKey: "key")
        XCTAssertEqual(backingStore.items, [root.path: .directory, path("key"): .file(data)])
    }

    func testSaveNeverReplacesAnotherScopesItem() throws {
        let cases: [(items: Items, occupied: URL)] = [
            (noValue[2], file("key")),  // a namespace's folder at the file's path
            (noValue[3], file("key")),  // a link at the file's path
            (noValue[4], root),         // a value of the scope around it where the folder goes
            (noValue[5], root)          // a link where the folder goes
        ]

        for (items, occupied) in cases {
            // Given
            let backingStore = FileBackingStoreMock()
            backingStore.items = items

            // When - Then
            assertThrows(FileStorage.Error.pathOccupied(occupied)) { try makeStorage(backingStore).save(data, forKey: "key") }
            XCTAssertEqual(backingStore.items, items)
        }
    }

    // MARK: Delete

    func testDeleteRemovesTheFile() throws {
        // Given
        backingStore.items = [root.path: .directory, path("key"): .file(data), path("other"): .file(data)]

        // When
        try makeStorage().delete(forKey: "key")

        // Then
        XCTAssertEqual(backingStore.items, [root.path: .directory, path("other"): .file(data)])
    }

    // MARK: Clear

    func testClearRemovesOnlyTheScopesFiles() throws {
        // Given: the scope's files, next to SQLite's, files no key produces, and a folder with a key's name
        let foreign: Items = [
            path(".KeyValueStorage.sqlite"): .file(data),
            path(".DS_Store"): .file(data),
            path("%2E"): .file(data),
            path("%41"): .file(data),
            path("Notes"): .file(data),
            path("notes.txt"): .file(data),
            path("100%"): .file(data),
            path("settings"): .directory,
            path("settings/theme"): .file(data)
        ]
        backingStore.items = foreign.merging([root.path: .directory, path("key"): .file(data), path("!key"): .file(data)]) { $1 }

        // When
        try makeStorage().clear()

        // Then
        XCTAssertEqual(backingStore.items, foreign.merging([root.path: .directory]) { $1 })
    }

    func testClearSkipsFilesWhoseKeyHasAnotherName() throws {
        // Given: a locator whose two name methods disagree
        let locator = FileLocatorStub()
        locator.keys = ["stale-key": "key", "located-other": "other"]
        let folder = locator.directory
        backingStore.items = [
            folder.path: .directory,
            folder.appendingPathComponent("stale-key").path: .file(data),
            folder.appendingPathComponent("located-other").path: .file(data)
        ]

        // When
        try FileStorage(scope: scope, backingStore: backingStore, locator: locator).clear()

        // Then
        XCTAssertEqual(backingStore.items, [folder.path: .directory, folder.appendingPathComponent("stale-key").path: .file(data)])
    }

    func testClearWithoutAFolderDoesNothing() throws {
        for items in [noValue[0], noValue[4], noValue[5]] {
            // Given
            let backingStore = FileBackingStoreMock()
            backingStore.items = items

            // When
            try makeStorage(backingStore).clear()

            // Then
            XCTAssertEqual(backingStore.items, items)
            XCTAssertEqual(backingStore.calls, [.itemType(root)])
        }
    }

    func testClearStopsAtTheFirstFailure() throws {
        // Given
        let error = POSIXError(.EACCES)
        backingStore.items = [root.path: .directory, path("a"): .file(data), path("b"): .file(data), path("c"): .file(data)]
        backingStore.errors = [(.remove(file("b")), error)]

        // When - Then
        assertThrows(FileStorage.Error.other(error)) { try makeStorage().clear() }
        XCTAssertEqual(backingStore.items, [root.path: .directory, path("b"): .file(data), path("c"): .file(data)])
    }

    // MARK: Set

    func testSetSavesAValueAndDeletesNil() throws {
        // Given
        let storage = try makeStorage()

        // When - Then
        try storage.set(data, forKey: "key")
        XCTAssertEqual(backingStore.items, [root.path: .directory, path("key"): .file(data)])
        try storage.set(nil, forKey: "key")
        XCTAssertEqual(backingStore.items, [root.path: .directory])
    }

    // MARK: Errors

    func testEveryFileSystemErrorIsReportedNeverTakenForNoValue() throws {
        let error = fileSystemError(.fileReadNoPermission, .EACCES)
        let value: Items = [root.path: .directory, path("key"): .file(data)]
        let operations: [(name: String, items: Items, run: (FileStorage) throws -> Void)] = [
            ("fetch", value, { _ = try $0.fetch(forKey: "key") }),
            ("save", [:], { [data] in try $0.save(data, forKey: "key") }),
            ("delete", value, { try $0.delete(forKey: "key") }),
            ("clear", value, { try $0.clear() })
        ]

        for operation in operations {
            // Given: the calls the operation makes when nothing fails
            let succeeding = FileBackingStoreMock()
            succeeding.items = operation.items
            try operation.run(makeStorage(succeeding))

            for call in succeeding.calls {
                // Given
                let failing = FileBackingStoreMock()
                failing.items = operation.items
                failing.errors = [(call, error)]

                // When - Then
                assertThrows(FileStorage.Error.other(error)) { try operation.run(makeStorage(failing)) }
            }
        }
    }

    func testProtectedDataIsReportedAsSuch() throws {
        // Given
        let error = fileSystemError(.fileReadNoPermission, .EPERM)
        backingStore.items = [root.path: .directory, path("key"): .file(data)]
        backingStore.errors = [(.read(file("key")), error), (.write(data, file("key"), .atomic), fileSystemError(.fileWriteNoPermission, .EPERM))]
        let storage = try makeStorage()

        // When - Then
        assertThrows(FileStorage.Error.protectedDataUnavailable) { try storage.fetch(forKey: "key") }
        assertThrows(FileStorage.Error.protectedDataUnavailable) { try storage.save(data, forKey: "key") }
    }

    func testOnlyEPERMUnderAPermissionErrorMeansProtectedData() throws {
        let cocoaUnderlying = NSError(domain: NSCocoaErrorDomain, code: 0)
        let notProtected: [NSError] = [
            fileSystemError(.fileReadUnknown, .EPERM),                       // another code
            NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)),          // another domain
            fileSystemError(.fileReadNoPermission),                          // no underlying error
            NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadNoPermission.rawValue, userInfo: [NSUnderlyingErrorKey: cocoaUnderlying]),
            fileSystemError(.fileReadNoPermission, .EACCES)                  // another POSIX code
        ]

        for error in notProtected {
            // Given
            let backingStore = FileBackingStoreMock()
            backingStore.items = [root.path: .directory, path("key"): .file(data)]
            backingStore.errors = [(.read(file("key")), error)]

            // When - Then
            assertThrows(FileStorage.Error.other(error)) { try makeStorage(backingStore).fetch(forKey: "key") }
        }
    }

    // MARK: Helpers

    private func makeStorage(_ backingStore: FileBackingStoreMock? = nil) throws(FileStorage.Error) -> FileStorage {
        try FileStorage(scope: scope, backingStore: backingStore ?? self.backingStore, locator: DefaultFileLocator())
    }

    private func file(_ name: String) -> URL {
        root.appendingPathComponent(name, isDirectory: false)
    }

    private func path(_ name: String) -> String {
        file(name).path
    }
}
