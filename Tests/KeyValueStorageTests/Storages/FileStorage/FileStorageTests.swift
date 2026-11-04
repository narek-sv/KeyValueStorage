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

    /// `scope`'s folder, as `FixedDirectoriesFileLocator` names it.
    private let root = URL(fileURLWithPath: "/support/com%2etest%2e!app/name!/i", isDirectory: true)
    /// Where `clear()` moves `root`, in the mock's temporary folder.
    private let movedRoot = FileBackingStoreMock.temporaryFolder.appendingPathComponent("i", isDirectory: true)
    private let scope = FileStorage.Scope.own(namespace: "name")
    private let data = Data([0xAA, 0xBB])
    private let backingStore = FileBackingStoreMock()

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
        let folders: [(FileStorage.Scope, String)] = [
            (.own(.temporary, namespace: "name"), "/temporary/com%2etest%2e!app/name!/i"),
            (.appGroup(id: "group.test", protection: .whenUnlocked, namespace: "name"), "/group/name!/w")
        ]

        for (scope, folder) in folders {
            // When
            let backingStore = FileBackingStoreMock()
            let storage = try FileStorage(scope: scope, backingStore: backingStore, locator: FixedDirectoriesFileLocator())

            // Then
            XCTAssertEqual(backingStore.calls, [])
            try storage.save(data, forKey: "key")
            XCTAssertEqual(backingStore.items[folder + "/key"], .file(data))
        }
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
        let storage = try FileStorage(scope: scope, backingStore: backingStore, locator: locator)
        let folder = locator.directory.path
        let file = locator.directory.appendingPathComponent("located-key").path

        // When - Then
        try storage.save(data, forKey: "key")
        XCTAssertEqual(backingStore.items, [folder: .directory, file: .file(data)])
        XCTAssertEqual(try storage.fetch(forKey: "key"), data)
        try storage.delete(forKey: "key")
        XCTAssertEqual(backingStore.items, [folder: .directory])

        try storage.save(data, forKey: "key")
        try storage.clear()
        XCTAssertEqual(backingStore.items, [:])
        let moved = FileBackingStoreMock.temporaryFolder.appendingPathComponent("located", isDirectory: true)
        XCTAssertTrue(backingStore.calls.contains(.move(locator.directory, moved)))

        XCTAssertEqual(locator.calls, [
            .directory(scope),
            .fileName("key", scope),
            .fileName("key", scope),
            .fileName("key", scope),
            .fileName("key", scope)
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
        let key = FileStorage.Key(String(repeating: "a", count: 256))
        let expected = FileStorage.Error.invalidKey(key)

        // When - Then
        assertThrows(expected) { try storage.fetch(forKey: key) }
        assertThrows(expected) { try storage.save(data, forKey: key) }
        assertThrows(expected) { try storage.delete(forKey: key) }
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

            // When
            let fetched = try makeStorage(backingStore).fetch(forKey: "key")

            // Then: nothing is read
            XCTAssertNil(fetched, "\(items)")
            XCTAssertFalse(backingStore.calls.contains(.read(file("key"))), "\(items)")
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

    func testAFileRemovedByAnotherCallSinceTheCheckFetchesAsNoValue() throws {
        // Given: the check finds the file, and another call removes it before this one reads it
        backingStore.items = [root.path: .directory, path("key"): .file(data)]
        backingStore.errors = [(.read(file("key")), CocoaError(.fileReadNoSuchFile))]

        // When - Then
        XCTAssertNil(try makeStorage().fetch(forKey: "key"))
    }

    // MARK: Save

    func testSaveWritesAtomicallyWithTheScopesProtection() throws {
        // Given
        let options: [(FileStorage.Protection, Data.WritingOptions)] = [
            (.inherited, .atomic),
            (.none, [.atomic, .noFileProtection]),
            (.afterFirstUnlock, [.atomic, .completeFileProtectionUntilFirstUserAuthentication]),
            (.whenUnlocked, [.atomic, .completeFileProtection]),
            (.whenUnlockedOrOpen, [.atomic, .completeFileProtectionUnlessOpen])
        ]

        // When
        for (protection, _) in options {
            let storage = try FileStorage(scope: .own(protection: protection, namespace: "name"), backingStore: backingStore, locator: FixedDirectoriesFileLocator())
            try storage.save(data, forKey: "key")
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

    func testASaveWhoseFolderAClearMovesOutSavesOnceMoreIntoANewOne() throws {
        // Given: the folder, which a clear moves out right before the first write
        backingStore.items = [root.path: .directory]
        backingStore.beforeWrite = { [root] backingStore in
            backingStore.items[root.path] = nil
            backingStore.beforeWrite = nil
        }

        // When
        try makeStorage().save(data, forKey: "key")

        // Then: the second write made a new folder
        XCTAssertEqual(backingStore.items, [root.path: .directory, path("key"): .file(data)])
        XCTAssertEqual(backingStore.calls.filter { if case .write = $0 { true } else { false } }.count, 2)
        XCTAssertEqual(backingStore.calls.suffix(3), [.createDirectory(root), .itemType(file("key")), .write(data, file("key"), .atomic)])
    }

    func testASaveTriesOnlyOnceMore() throws {
        // Given: a clear before every write
        backingStore.beforeWrite = { [root] backingStore in
            backingStore.items[root.path] = nil
        }

        // When - Then
        assertThrows(FileStorage.Error.other(CocoaError(.fileNoSuchFile))) { try makeStorage().save(data, forKey: "key") }
        XCTAssertEqual(backingStore.calls.filter { if case .write = $0 { true } else { false } }.count, 2)
    }

    func testASaveThatFailsWithItsFolderInPlaceIsntTriedAgain() throws {
        // Given
        let error = fileSystemError(.fileWriteUnknown)
        backingStore.items = [root.path: .directory]
        backingStore.errors = [(.write(data, file("key"), .atomic), error)]

        // When - Then
        assertThrows(FileStorage.Error.other(error)) { try makeStorage().save(data, forKey: "key") }
        XCTAssertEqual(backingStore.calls.filter { if case .write = $0 { true } else { false } }.count, 1)
    }

    // MARK: Backups

    func testSavesExcludedFromBackupFlagTheFolderBeforeEveryWrite() throws {
        // Given
        let root = URL(fileURLWithPath: "/support/com%2etest%2e!app/x/name!/i", isDirectory: true)
        let file = root.appendingPathComponent("key", isDirectory: false)
        let storage = try FileStorage(scope: .own(.persistentExcludedFromBackup, namespace: "name"), backingStore: backingStore, locator: FixedDirectoriesFileLocator())

        // When: the first save creates the folder, the second finds it
        try storage.save(data, forKey: "key")
        try storage.save(data, forKey: "key")

        // Then
        let flagAndWrite: [FileBackingStoreMock.Call] = [.excludeFromBackup(root), .itemType(file), .write(data, file, .atomic)]
        XCTAssertEqual(backingStore.calls, [.itemType(root), .createDirectory(root)] + flagAndWrite + [.itemType(root)] + flagAndWrite)
    }

    func testSavesInEveryOtherScopeLeaveTheFolderAsItIs() throws {
        let scopes: [FileStorage.Scope] = [
            .own(.persistent, namespace: "name"), .own(.cache, namespace: "name"), .own(.temporary, namespace: "name"),
            .appGroup(id: "group.test", namespace: "name")
        ]

        for scope in scopes {
            // When
            let backingStore = FileBackingStoreMock()
            try FileStorage(scope: scope, backingStore: backingStore, locator: FixedDirectoriesFileLocator()).save(data, forKey: "key")

            // Then
            XCTAssertFalse(backingStore.calls.contains { if case .excludeFromBackup = $0 { true } else { false } }, "\(scope)")
        }
    }

    func testAFolderThatCantBeFlaggedGetsNoValueUntilASaveFlagsIt() throws {
        // Given
        let root = URL(fileURLWithPath: "/support/com%2etest%2e!app/x/name!/i", isDirectory: true)
        let error = fileSystemError(.fileWriteUnknown)
        backingStore.errors = [(.excludeFromBackup(root), error)]
        let storage = try FileStorage(scope: .own(.persistentExcludedFromBackup, namespace: "name"), backingStore: backingStore, locator: FixedDirectoriesFileLocator())

        // When - Then: the folder it created stays, without a value
        assertThrows(FileStorage.Error.other(error)) { try storage.save(data, forKey: "key") }
        XCTAssertEqual(backingStore.items, [root.path: .directory])

        // When - Then: the next save flags the folder it finds, then writes
        backingStore.errors = []
        try storage.save(data, forKey: "key")
        XCTAssertEqual(backingStore.items, [root.path: .directory, root.appendingPathComponent("key").path: .file(data)])
        XCTAssertEqual(backingStore.calls.filter { $0 == .excludeFromBackup(root) }.count, 2)
    }

    // MARK: Delete

    func testDeleteRemovesTheFileWithOneCallAfterTheFolder() throws {
        // Given
        backingStore.items = [root.path: .directory, path("key"): .file(data), path("other"): .file(data)]

        // When
        try makeStorage().delete(forKey: "key")

        // Then
        XCTAssertEqual(backingStore.items, [root.path: .directory, path("other"): .file(data)])
        XCTAssertEqual(backingStore.calls, [.itemType(root), .remove(file("key"))])
    }

    func testDeleteWithoutTheFolderChangesNothing() throws {
        // A link where the folder goes is never followed
        for items in [noValue[0], noValue[4], noValue[5]] {
            // Given
            let backingStore = FileBackingStoreMock()
            backingStore.items = items

            // When
            try makeStorage(backingStore).delete(forKey: "key")

            // Then
            XCTAssertEqual(backingStore.items, items)
            XCTAssertEqual(backingStore.calls, [.itemType(root)])
        }
    }

    func testDeleteWithoutAFileInTheFolderChangesNothing() throws {
        // Given
        backingStore.items = [root.path: .directory]

        // When
        try makeStorage().delete(forKey: "key")

        // Then
        XCTAssertEqual(backingStore.items, [root.path: .directory])
        XCTAssertEqual(backingStore.calls, [.itemType(root), .remove(file("key"))])
    }

    func testDeleteRemovesALinkInTheFilesPlaceButLeavesAFolder() throws {
        // Given
        let folder: Items = [root.path: .directory, path("key"): .directory, path("key/inner"): .file(data)]

        // When - Then: the link goes, but never what it points to
        backingStore.items = [root.path: .directory, path("key"): .link]
        try makeStorage().delete(forKey: "key")
        XCTAssertEqual(backingStore.items, [root.path: .directory])

        // When - Then: `remove` refuses the folder, which stays, and that's no error
        let folderStore = FileBackingStoreMock()
        folderStore.items = folder
        try makeStorage(folderStore).delete(forKey: "key")
        XCTAssertEqual(folderStore.items, folder)
        XCTAssertEqual(folderStore.calls, [.itemType(root), .remove(file("key")), .itemType(file("key"))])
    }

    func testAFileRemovedByAnotherCallSinceTheCheckIsDeleted() throws {
        // Given: the check finds the folder, and another call removes the file before this one does
        backingStore.items = [root.path: .directory, path("key"): .file(data)]
        backingStore.errors = [(.remove(file("key")), FileItemError.notFound)]

        // When - Then
        try makeStorage().delete(forKey: "key")
    }

    func testARemovalThatIsntPermittedIsProtectedDataUnlessItsAFolder() throws {
        let cases: [(items: Items, error: FileStorage.Error?)] = [
            ([root.path: .directory, path("key"): .file(data)], .protectedDataUnavailable),
            ([root.path: .directory, path("key"): .link], .protectedDataUnavailable),
            ([root.path: .directory, path("key"): .directory], nil),
            ([root.path: .directory], .protectedDataUnavailable)    // gone before the lookup
        ]

        for (items, expected) in cases {
            // Given
            let backingStore = FileBackingStoreMock()
            backingStore.items = items
            backingStore.errors = [(.remove(file("key")), FileItemError.notPermitted)]

            // When - Then
            if let expected {
                assertThrows(expected) { try makeStorage(backingStore).delete(forKey: "key") }
            } else {
                try makeStorage(backingStore).delete(forKey: "key")
            }
            XCTAssertEqual(backingStore.items, items)
        }
    }

    func testAFailedLookupAfterARefusedRemovalIsReported() throws {
        // Given
        backingStore.items = [root.path: .directory, path("key"): .file(data)]
        backingStore.errors = [(.remove(file("key")), FileItemError.notPermitted), (.itemType(file("key")), FileItemError.other(EIO))]

        // When - Then
        assertThrows(FileStorage.Error.other(FileItemError.other(EIO))) { try makeStorage().delete(forKey: "key") }
    }

    // MARK: Clear

    func testClearMovesTheWholeFolderOutInOneCallThenRemovesItInTheBackground() throws {
        // Given: values, items no save makes, and another scope's value
        let other = "/support/com%2etest%2e!app/other!/i/key"
        backingStore.items = [
            root.path: .directory, path("key"): .file(data), path("!key"): .file(data), path(".DS_Store"): .file(data),
            path("notes.txt"): .file(data), path("settings"): .directory, path("settings/theme"): .file(data), path("link"): .link,
            other: .file(data)
        ]

        // When
        try makeStorage().clear()

        // Then: everything in the scope's folder is gone, with the folder
        XCTAssertEqual(backingStore.items, [other: .file(data)])
        XCTAssertEqual(backingStore.calls, [
            .itemType(root),
            .itemReplacementDirectory(root),
            .move(root, movedRoot),
            .removeInBackground(FileBackingStoreMock.temporaryFolder)
        ])
    }

    func testClearMovesAnythingInTheFoldersPlace() throws {
        // A link goes, but never what it points to
        for items in [noValue[4], noValue[5]] {
            // Given
            let backingStore = FileBackingStoreMock()
            backingStore.items = items

            // When
            try makeStorage(backingStore).clear()

            // Then
            XCTAssertEqual(backingStore.items, [:])
        }
    }

    func testClearWithNothingInTheFoldersPlaceDoesNothing() throws {
        // When
        try makeStorage().clear()

        // Then
        XCTAssertEqual(backingStore.calls, [.itemType(root)])
    }

    func testAFolderMovedByAnotherClearSinceTheCheckIsCleared() throws {
        // Given
        backingStore.items = [root.path: .directory]
        backingStore.errors = [(.move(root, movedRoot), FileItemError.notFound)]

        // When
        try makeStorage().clear()

        // Then: the temporary folder goes too
        XCTAssertEqual(backingStore.calls.last, .removeInBackground(FileBackingStoreMock.temporaryFolder))
    }

    func testAClearThatFailsChangesNothing() throws {
        let moveError = FileItemError.other(EACCES)
        let folderError = fileSystemError(.fileWriteUnknown)
        let cases: [(call: FileBackingStoreMock.Call, error: any Error, expected: FileStorage.Error, madeTemporaryFolder: Bool)] = [
            (.itemType(root), FileItemError.notPermitted, .protectedDataUnavailable, false),
            (.itemReplacementDirectory(root), folderError, .other(folderError), false),
            (.move(root, movedRoot), moveError, .other(moveError), true),
            (.move(root, movedRoot), FileItemError.notPermitted, .protectedDataUnavailable, true)
        ]
        let items: Items = [root.path: .directory, path("key"): .file(data)]

        for (call, error, expected, madeTemporaryFolder) in cases {
            // Given
            let backingStore = FileBackingStoreMock()
            backingStore.items = items
            backingStore.errors = [(call, error)]

            // When - Then: the scope keeps every value, and a temporary folder it made goes
            assertThrows(expected) { try makeStorage(backingStore).clear() }
            XCTAssertEqual(backingStore.items, items)
            XCTAssertEqual(backingStore.calls.contains(.removeInBackground(FileBackingStoreMock.temporaryFolder)), madeTemporaryFolder, "\(call)")
        }
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
        let fileSystem = fileSystemError(.fileReadNoPermission, .EACCES)
        let lookup = FileItemError.other(EACCES)
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
                // Given: a failure of each call that can fail
                if case .removeInBackground = call {
                    continue
                }

                let failing = FileBackingStoreMock()
                failing.items = operation.items
                let error: any Error = switch call {
                case .itemType, .remove, .move:     lookup
                default:                            fileSystem
                }
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

    func testALookupThatIsntPermittedIsProtectedDataInEveryOperation() throws {
        // Every lookup each operation makes: `delete` and `clear()` look up only the folder
        let operations: [(name: String, urls: [URL], run: (FileStorage) throws -> Void)] = [
            ("fetch", [root, file("key")], { _ = try $0.fetch(forKey: "key") }),
            ("save", [root, file("key")], { [data] in try $0.save(data, forKey: "key") }),
            ("delete", [root], { try $0.delete(forKey: "key") }),
            ("clear", [root], { try $0.clear() })
        ]

        for operation in operations {
            for url in operation.urls {
                // Given: the folder's lookup fails, or the file's
                let backingStore = FileBackingStoreMock()
                backingStore.items = [root.path: .directory, path("key"): .file(data)]
                backingStore.errors = [(.itemType(url), FileItemError.notPermitted)]

                // When - Then
                assertThrows(FileStorage.Error.protectedDataUnavailable) { try operation.run(makeStorage(backingStore)) }
                XCTAssertEqual(backingStore.items, [root.path: .directory, path("key"): .file(data)], "\(operation.name), \(url)")
            }
        }
    }

    func testEveryOtherLookupFailureKeepsItsCode() throws {
        for code in [EACCES, ENOTDIR, ENAMETOOLONG, ELOOP, EIO, EINVAL] {
            // Given
            let backingStore = FileBackingStoreMock()
            backingStore.items = [root.path: .directory, path("key"): .file(data)]
            backingStore.errors = [(.itemType(file("key")), FileItemError(code: code))]

            // When - Then
            assertThrows(FileStorage.Error.other(FileItemError.other(code))) { try makeStorage(backingStore).fetch(forKey: "key") }
        }
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
        try FileStorage(scope: scope, backingStore: backingStore ?? self.backingStore, locator: FixedDirectoriesFileLocator())
    }

    private func file(_ name: String) -> URL {
        root.appendingPathComponent(name, isDirectory: false)
    }

    private func path(_ name: String) -> String {
        file(name).path
    }
}
