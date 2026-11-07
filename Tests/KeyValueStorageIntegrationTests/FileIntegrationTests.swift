//
//  FileIntegrationTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 28.10.26.
//

import XCTest
import Foundation
import KeyValueStorage // not @testable: the real file system through the public API

/// The default backing store and locator against the real file system, in a temporary folder of each test's own.
final class FileIntegrationTests: XCTestCase {
    private let fileManager = FileManager.default
    private var base: URL!
    private var locator: TestFileLocator!

    override func setUpWithError() throws {
        let base = fileManager.temporaryDirectory.appendingPathComponent("FileIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        self.base = base
        locator = TestFileLocator(base: base)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: base)
        }
    }

    // MARK: Adapter

    func testItemTypesDescribeLinksThemselves() throws {
        // Given
        let adapter = DefaultFileBackingStoreWrapper()
        let file = try makeFile("file")
        let folder = try makeFolder("folder")

        // When - Then
        XCTAssertEqual(try adapter.itemType(at: file), .typeRegular)
        XCTAssertEqual(try adapter.itemType(at: folder), .typeDirectory)
        XCTAssertEqual(try adapter.itemType(at: makeLink("linkToFile", to: file)), .typeSymbolicLink)
        XCTAssertEqual(try adapter.itemType(at: makeLink("linkToFolder", to: folder)), .typeSymbolicLink)
        XCTAssertEqual(try adapter.itemType(at: makeLink("dangling", to: base.appendingPathComponent("missing"))), .typeSymbolicLink)
    }

    func testOtherItemTypesAreReported() throws {
        // Given
        let adapter = DefaultFileBackingStoreWrapper()
        let fifo = base.appendingPathComponent("fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o644), 0)

        // When - Then: no value, and never a regular file
        XCTAssertEqual(try adapter.itemType(at: fifo), .typeUnknown)
        #if os(macOS)
        XCTAssertEqual(try adapter.itemType(at: URL(fileURLWithPath: "/dev/null")), .typeCharacterSpecial)
        #endif
    }

    /// `FileStorage` takes `.notFound` for "nothing is there", and every other failure for an error.
    func testOnlyAMissingItemIsNotFound() throws {
        // Given
        let adapter = DefaultFileBackingStoreWrapper()
        let underFile = try makeFile("file").appendingPathComponent("key")
        let tooLong = base.appendingPathComponent(Array(repeating: String(repeating: "d", count: 200), count: 6).joined(separator: "/"))

        // When - Then
        XCTAssertThrowsError(try adapter.itemType(at: base.appendingPathComponent("missing"))) { error in
            XCTAssertEqual(error as? FileItemError, .notFound)
        }

        XCTAssertThrowsError(try adapter.itemType(at: underFile)) { error in
            XCTAssertEqual(error as? FileItemError, .other(ENOTDIR))
        }

        XCTAssertThrowsError(try adapter.itemType(at: tooLong)) { error in
            XCTAssertEqual(error as? FileItemError, .other(ENAMETOOLONG))
        }

        try XCTSkipIf(getuid() == 0, "File permissions are not enforced for root")
        let locked = try makeFolder("locked")
        try setPermissions(0o000, of: locked)
        XCTAssertThrowsError(try adapter.itemType(at: locked.appendingPathComponent("inner"))) { error in
            XCTAssertEqual(error as? FileItemError, .other(EACCES))
        }
    }

    func testRemoveDeletesAFileOrALinkButNeverAFolder() throws {
        // Given
        let adapter = DefaultFileBackingStoreWrapper()
        let file = try makeFile("file")
        let folder = try makeFolder("folder")
        let links = [
            try makeLink("toFile", to: file),
            try makeLink("toFolder", to: folder),
            try makeLink("dangling", to: base.appendingPathComponent("missing"))
        ]

        // When - Then: each link goes, never what it points to
        for link in links {
            try adapter.remove(at: link)
        }

        XCTAssertEqual(Set(try fileManager.contentsOfDirectory(atPath: base.path)), ["file", "folder"])
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("inner").path))
        try adapter.remove(at: file)
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: base.path), ["folder"])

        // When - Then: a folder stays whole
        XCTAssertThrowsError(try adapter.remove(at: folder)) { error in
            XCTAssertEqual(error as? FileItemError, .notPermitted)
        }

        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("inner").path))
        XCTAssertThrowsError(try adapter.remove(at: base.appendingPathComponent("missing"))) { error in
            XCTAssertEqual(error as? FileItemError, .notFound)
        }

        XCTAssertThrowsError(try adapter.remove(at: makeFile("plain").appendingPathComponent("key"))) { error in
            XCTAssertEqual(error as? FileItemError, .other(ENOTDIR))
        }
    }

    func testMoveTakesAFolderWholeAndALinkItself() throws {
        // Given
        let adapter = DefaultFileBackingStoreWrapper()
        let folder = try makeFolder("folder")
        let target = try makeFile("target")
        let link = try makeLink("link", to: target)
        let destination = try makeFolder(base.appendingPathComponent("destination", isDirectory: true))

        // When
        try adapter.move(at: folder, to: destination.appendingPathComponent("folder", isDirectory: true))
        try adapter.move(at: link, to: destination.appendingPathComponent("link", isDirectory: false))

        // Then
        XCTAssertEqual(Set(try fileManager.contentsOfDirectory(atPath: base.path)), ["destination", "target"])
        XCTAssertTrue(fileManager.fileExists(atPath: destination.appendingPathComponent("folder/inner").path))
        XCTAssertEqual(try adapter.itemType(at: destination.appendingPathComponent("link")), .typeSymbolicLink)
        XCTAssertEqual(try Data(contentsOf: target), Data([1]))
        let missing = base.appendingPathComponent("missing")
        XCTAssertThrowsError(try adapter.move(at: missing, to: destination.appendingPathComponent("missing"))) { error in
            XCTAssertEqual(error as? FileItemError, .notFound)
        }
    }

    func testEachItemReplacementDirectoryIsANewEmptyFolderOnTheVolume() throws {
        // Given
        let adapter = DefaultFileBackingStoreWrapper()
        let folder = try makeFolder("folder")

        // When
        let first = try adapter.itemReplacementDirectory(appropriateFor: folder)
        let second = try adapter.itemReplacementDirectory(appropriateFor: folder)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        // Then: a move into it works, which takes the same volume
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: first.path), [])
        try adapter.move(at: folder, to: first.appendingPathComponent("folder", isDirectory: true))
        XCTAssertTrue(fileManager.fileExists(atPath: first.appendingPathComponent("folder/inner").path))
    }

    func testRemoveInBackgroundRemovesAFolderWithEverythingInside() async throws {
        // Given
        let adapter = DefaultFileBackingStoreWrapper()
        let folder = try makeFolder("folder")

        // When
        adapter.removeInBackground(at: folder)

        // Then
        try await waitUntilGone(folder)
    }

    func testTheLocatorsLookupsReturnTheSystemsDirectories() {
        let locator = DefaultFileLocator()

        XCTAssertEqual(locator.temporaryDirectory, fileManager.temporaryDirectory)
        XCTAssertEqual(locator.systemDirectory(.applicationSupportDirectory), fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        XCTAssertEqual(locator.systemDirectory(.cachesDirectory), fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let groupId = "group.not.entitled.\(UUID().uuidString)"
        XCTAssertEqual(locator.groupDirectory(for: groupId), fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupId))
        XCTAssertEqual(locator.ownIdentifier, OwnIdentity.identifier)
    }

    /// Measured, for `.appGroup`'s doc in File and SQLite.
    func testWhichGroupIdsTheSystemGivesAContainer() throws {
        // Given: a group this test process isn't entitled to, and the same id in capitals
        let groupId = "group.not.entitled.\(UUID().uuidString.lowercased())"
        let containers = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Group Containers", isDirectory: true)
        let before = (try? fileManager.contentsOfDirectory(atPath: containers.path)) ?? []

        // When
        let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupId)
        let capitalized = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupId.uppercased())
        let empty = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "")

        // Then
        XCTAssertNil(empty)
        #if os(macOS)
        // Any other id gets a path, and nothing is created until a value is saved
        let path = try XCTUnwrap(container).path
        let capitalizedPath = try XCTUnwrap(capitalized).path
        XCTAssertFalse(fileManager.fileExists(atPath: path))
        XCTAssertEqual((try? fileManager.contentsOfDirectory(atPath: containers.path)) ?? [], before)
        // Ids that differ only in case get paths that differ only in case, which a volume that ignores case takes for one
        XCTAssertNotEqual(path, capitalizedPath)
        XCTAssertEqual(path.lowercased(), capitalizedPath.lowercased())
        #elseif targetEnvironment(simulator)
        // The Simulator doesn't check entitlements: any id gets a container of its own, also ids that differ only in case
        XCTAssertNotNil(container)
        XCTAssertNotNil(capitalized)
        XCTAssertNotEqual(container, capitalized)
        _ = before
        #else
        // A device gives only the app's own groups a container (to verify in the device run)
        XCTAssertNil(container)
        XCTAssertNil(capitalized)
        _ = before
        #endif
    }

    // MARK: Values

    func testAKeyWithTheLongestFileNameWorksInEveryOperation() throws {
        // Given: a key whose file name is 255 bytes, the most a name can have; an atomic save writes through a temporary
        // file, whose name mustn't need more
        let storage = try storage()
        let key = FileStorage.Key(String(repeating: "a", count: 255))

        // When - Then
        try storage.save(Data([1]), forKey: key)
        try storage.save(Data([2]), forKey: key)
        XCTAssertEqual(try storage.fetch(forKey: key), Data([2]))
        try storage.delete(forKey: key)
        XCTAssertNil(try storage.fetch(forKey: key))
        try storage.save(Data([3]), forKey: key)
        try storage.clear()
        XCTAssertNil(try storage.fetch(forKey: key))
    }

    func testValuesRoundTripInFilesNamedAfterTheirKeys() throws {
        // Given
        let storage = try storage(.own(namespace: "values"))
        let folder = try folder(.own(namespace: "values"))

        // When
        try storage.save(Data([1]), forKey: "key")
        try storage.save(Data([2]), forKey: "Key")
        try storage.save(Data([3]), forKey: "\u{E9}")
        try storage.save(Data([4]), forKey: "e\u{301}")

        // Then: keys that differ only in case, and the two spellings of `é`, have files of their own
        XCTAssertEqual(folder.path, base.appendingPathComponent("support/app/values!/i").path)
        XCTAssertEqual(try storage.fetch(forKey: "key"), Data([1]))
        XCTAssertEqual(try storage.fetch(forKey: "Key"), Data([2]))
        XCTAssertEqual(try storage.fetch(forKey: "\u{E9}"), Data([3]))
        XCTAssertEqual(try storage.fetch(forKey: "e\u{301}"), Data([4]))
        XCTAssertEqual(Set(try fileManager.contentsOfDirectory(atPath: folder.path)).count, 4)

        // When
        try storage.delete(forKey: "key")

        // Then
        XCTAssertNil(try storage.fetch(forKey: "key"))
        XCTAssertEqual(try storage.fetch(forKey: "Key"), Data([2]))
    }

    func testEveryShortASCIIKeyHasAFileOfItsOwn() throws {
        // Given: every key of up to two printable ASCII characters, so every pair that differs only in case
        let storage = try storage()
        let characters = (0x20...0x7E).map { String(UnicodeScalar(UInt8($0))) }
        let keys = [""] + characters + characters.flatMap { first in characters.map { first + $0 } }

        // When
        for key in keys {
            try storage.save(Data(key.utf8), forKey: .init(key))
        }

        // Then
        for key in keys {
            XCTAssertEqual(try storage.fetch(forKey: .init(key)), Data(key.utf8), key.debugDescription)
        }

        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: folder().path).count, keys.count)
        try storage.clear()
        XCTAssertFalse(fileManager.fileExists(atPath: try folder().path))
    }

    func testOnlySavesCreateTheFolder() throws {
        // Given
        let storage = try storage(.own(namespace: "lazy"))

        // When
        XCTAssertNil(try storage.fetch(forKey: "key"))
        try storage.delete(forKey: "key")
        try storage.clear()

        // Then
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: base.path), [])

        // When
        try storage.save(Data([1]), forKey: "key")

        // Then
        XCTAssertTrue(fileManager.fileExists(atPath: try folder(.own(namespace: "lazy")).appendingPathComponent("key").path))
    }

    func testInstancesSharingAFolderSeeEachOthersChanges() throws {
        // Given
        let first = try storage()
        let second = try storage()

        // When - Then
        try first.save(Data([1]), forKey: "key")
        XCTAssertEqual(try second.fetch(forKey: "key"), Data([1]))
        try second.save(Data([2]), forKey: "key")
        XCTAssertEqual(try first.fetch(forKey: "key"), Data([2]))
        try second.clear()
        XCTAssertNil(try first.fetch(forKey: "key"))
    }

    func testOverwriteNeverExposesAMissingOrPartialValue() throws {
        // Given
        let storage = try storage()
        let values = [Data(repeating: 0x01, count: 64 * 1024), Data(repeating: 0x02, count: 256 * 1024)]
        try storage.save(values[0], forKey: "key")
        let reader = ConcurrentReader(url: try folder().appendingPathComponent("key"), expectedValues: values)

        // When
        reader.start()
        for index in 0..<300 {
            try storage.save(values[index % 2], forKey: "key")
        }
        let result = reader.stop()

        // Then
        XCTAssertGreaterThan(result.reads, 0)
        XCTAssertEqual(result.missing, 0)
        XCTAssertEqual(result.partial, 0)
    }

    func testAPathOverTheSystemsLimitIsReportedThoughEveryNameFits() throws {
        // Given: a base deep enough that a key's file passes the system's 1024-byte limit on a whole path, while each name
        // stays within 255 bytes
        let deepLocator = TestFileLocator(base: try deepFolder(length: 900))
        let storage = try FileStorage(scope: .own(namespace: "test"), backingStore: DefaultFileBackingStoreWrapper(), locator: deepLocator)
        let folder = try deepLocator.directory(for: .own(namespace: "test")).path.utf8.count
        let fits = FileStorage.Key(String(repeating: "a", count: 1000 - folder - 1))
        let tooLong = FileStorage.Key(String(repeating: "a", count: 1100 - folder - 1))

        // When - Then
        try storage.save(Data([1]), forKey: fits)
        XCTAssertEqual(try storage.fetch(forKey: fits), Data([1]))
        assertOther(storageError { try storage.save(Data([2]), forKey: tooLong) }, posix: .ENAMETOOLONG)

        // The system can't even look the path up, so there's no telling whether a value is there
        for body in [{ _ = try storage.fetch(forKey: tooLong) }, { try storage.delete(forKey: tooLong) }] {
            assertOther(storageError(body), posix: .ENAMETOOLONG)
        }
    }

    // MARK: Concurrency

    func testConcurrentDeletesOfOneFileAllSucceed() throws {
        // Given
        let storage = try storage()
        try storage.save(Data([1]), forKey: "key")
        let failures = Failures()

        // When: 100 threads delete the same file at once
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            do {
                try storage.delete(forKey: "key")
            } catch {
                failures.append("\(error)")
            }
        }

        // Then
        XCTAssertEqual(failures.all, [])
        XCTAssertNil(try storage.fetch(forKey: "key"))
    }

    func testConcurrentClearsOfOneScopeAllSucceed() throws {
        // Given
        let storage = try storage()
        try storage.save(Data([1]), forKey: "key")
        let failures = Failures()

        // When: 100 threads clear the scope at once, and all but the first find its folder gone
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            do {
                try storage.clear()
            } catch {
                failures.append("\(error)")
            }
        }

        // Then
        XCTAssertEqual(failures.all, [])
        XCTAssertFalse(fileManager.fileExists(atPath: try folder().path))
    }

    func testFetchesRacingDeletesOfTheirFileFindTheValueOrNone() throws {
        // Given
        let storage = try storage()
        let value = Data([1])
        let fetches = Fetches()
        let failures = Failures()
        // Only stops threads that never overlap, which never find both
        let deadline = Date().addingTimeInterval(10)

        // When: one thread fetches the file while another deletes and saves it again, until the fetches have found the
        // file and found none 1,000 times each, which only overlapping threads do; both have returned when
        // `concurrentPerform` does
        DispatchQueue.concurrentPerform(iterations: 2) { thread in
            while !fetches.foundBoth(1_000), Date() < deadline {
                do {
                    if thread == 0 {
                        let fetched = try storage.fetch(forKey: "key")
                        fetches.record(fetched)
                        if let fetched, fetched != value {
                            failures.append("fetched \(fetched)")
                        }
                    } else {
                        try storage.delete(forKey: "key")
                        try storage.save(value, forKey: "key")
                    }
                } catch {
                    failures.append("\(error)")
                }
            }
        }

        // Then: the threads overlapped, and no fetch failed
        XCTAssertGreaterThanOrEqual(fetches.found, 1_000)
        XCTAssertGreaterThanOrEqual(fetches.missing, 1_000)
        XCTAssertEqual(Set(failures.all), [])
    }

    // MARK: Backups

    func testOnlyAScopeExcludedFromBackupFlagsItsFolder() throws {
        // Given
        let excluded = FileStorage.Scope.own(.persistentExcludedFromBackup, namespace: "name")
        let persistent = FileStorage.Scope.own(namespace: "name")

        // When
        try storage(excluded).save(Data([1]), forKey: "key")
        try storage(persistent).save(Data([2]), forKey: "key")

        // Then
        XCTAssertEqual(try folder(excluded).path, base.appendingPathComponent("support/app/x/name!/i").path)
        XCTAssertEqual(try isExcludedFromBackup(folder(excluded)), true)
        XCTAssertEqual(try isExcludedFromBackup(folder(persistent)), false)
    }

    func testTheFolderASaveMakesAfterAClearIsExcludedFromBackupToo() throws {
        // Given
        let excluded = FileStorage.Scope.own(.persistentExcludedFromBackup, namespace: "name")
        let storage = try storage(excluded)
        try storage.save(Data([1]), forKey: "key")

        // When
        try storage.clear()
        try storage.save(Data([2]), forKey: "key")

        // Then
        XCTAssertEqual(try isExcludedFromBackup(folder(excluded)), true)
    }

    // MARK: Protection

    func testEachProtectionsFilesGetItsClass() throws {
        try skipUnlessDataProtectionApplies(in: base)

        // `.none` and `.inherited` can't be checked: macOS reports the default class for them
        let protections: [(FileStorage.Protection, FileProtectionType)] = [
            (.whenUnlocked, .complete),
            (.whenUnlockedOrOpen, .completeUnlessOpen),
            (.afterFirstUnlock, .completeUntilFirstUserAuthentication)
        ]

        for (protection, expected) in protections {
            // Given
            let scope = FileStorage.Scope.own(protection: protection, namespace: "test")
            let storage = try storage(scope)
            let file = try folder(scope).appendingPathComponent("key")

            // When - Then: a new file, a replaced one, and one in the folder a save makes after a clear
            try storage.save(Data([1]), forKey: "key")
            XCTAssertEqual(try protectionClass(of: file), expected, "\(protection)")
            try storage.save(Data([2]), forKey: "key")
            XCTAssertEqual(try protectionClass(of: file), expected, "\(protection)")
            try storage.clear()
            try storage.save(Data([3]), forKey: "key")
            XCTAssertEqual(try protectionClass(of: file), expected, "\(protection)")
        }
    }

    // MARK: Clashes

    func testScopesThatDifferOnlyInRetentionProtectionOrGroupKeepTheirValuesApart() throws {
        // Given: one namespace in every kind of place
        let scopes: [FileStorage.Scope] = [
            .own(namespace: "name"), .own(.persistentExcludedFromBackup, namespace: "name"), .own(.cache, namespace: "name"),
            .own(.temporary, namespace: "name"), .own(protection: .none, namespace: "name"), .appGroup(id: "group.test", namespace: "name")
        ]
        let storages = try scopes.map { try storage($0) }

        // When
        for (index, storage) in storages.enumerated() {
            try storage.save(Data([UInt8(index)]), forKey: "key")
        }

        try storages[0].clear()

        // Then
        XCTAssertNil(try storages[0].fetch(forKey: "key"))
        for (index, storage) in storages.enumerated().dropFirst() {
            XCTAssertEqual(try storage.fetch(forKey: "key"), Data([UInt8(index)]), "\(scopes[index])")
        }
    }

    func testAFolderAtAKeysPathIsNeverAValueAndOnlyClearRemovesIt() throws {
        // Given: another app's folder with a key's name
        let storage = try storage()
        let folder = try makeFolder("settings", in: makeScopeFolder())

        // When
        let fetched = try storage.fetch(forKey: "settings")
        try storage.delete(forKey: "settings")
        let error = storageError { try storage.save(Data([2]), forKey: "settings") }

        // Then
        XCTAssertNil(fetched)
        assertPathOccupied(error, folder)
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("inner").path))

        // When - Then
        try storage.clear()
        XCTAssertFalse(fileManager.fileExists(atPath: folder.path))
        try storage.save(Data([2]), forKey: "settings")
        XCTAssertEqual(try storage.fetch(forKey: "settings"), Data([2]))
    }

    func testAFileWhereTheScopesFolderGoesIsNeverAValueAndOnlyClearRemovesIt() throws {
        // Given
        let storage = try storage()
        let scopeFolder = try folder()
        let file = try makeFile(scopeFolder.lastPathComponent, in: makeFolder(scopeFolder.deletingLastPathComponent()))

        // When
        let fetched = try storage.fetch(forKey: "key")
        try storage.delete(forKey: "key")
        let error = storageError { try storage.save(Data([2]), forKey: "key") }

        // Then
        XCTAssertNil(fetched)
        assertPathOccupied(error, scopeFolder)
        XCTAssertEqual(try Data(contentsOf: file), Data([1]))

        // When - Then
        try storage.clear()
        XCTAssertFalse(fileManager.fileExists(atPath: file.path))
        try storage.save(Data([2]), forKey: "key")
        XCTAssertEqual(try storage.fetch(forKey: "key"), Data([2]))
    }

    func testClearRemovesEverythingInTheScopesFolderAndNothingElse() throws {
        // Given: two namespaces, the first one's SQLite database, and other code's items in the first one's folder
        let first = try storage(.own(namespace: "first"))
        let second = try storage(.own(namespace: "second"))
        try first.save(Data([1]), forKey: "key")
        try first.save(Data([1]), forKey: "Key")
        try second.save(Data([2]), forKey: "key")
        let folder = try folder(.own(namespace: "first"))
        let sqlite = try SQLiteStorage(scope: .own(namespace: "first"), backingStore: DefaultSQLiteBackingStoreWrapper(), locator: TestSQLiteLocator(base: base))
        try sqlite.save(Data([3]), forKey: "key")
        let outside = try makeFile("outside")
        try makeFile(".hidden", in: folder)
        try makeFile("Notes.txt", in: folder)
        try makeFolder("settings", in: folder)
        try makeLink("link", to: outside, in: folder)

        // When
        try first.clear()

        // Then: the folder is gone, and what the link pointed to stays
        XCTAssertFalse(fileManager.fileExists(atPath: folder.path))
        XCTAssertNil(try first.fetch(forKey: "key"))
        XCTAssertNil(try first.fetch(forKey: "Key"))
        XCTAssertEqual(try second.fetch(forKey: "key"), Data([2]))
        XCTAssertEqual(try sqlite.fetch(forKey: "key"), Data([3]))
        XCTAssertEqual(try Data(contentsOf: outside), Data([1]))
    }

    func testClearEmptiesTheScopeAtOnceAndDeletesItsFilesInTheBackground() async throws {
        // Given
        let backingStore = ObservedFileBackingStore()
        let storage = try FileStorage(scope: .own(namespace: "test"), backingStore: backingStore, locator: locator)
        try storage.save(Data([1]), forKey: "key")

        // When
        try storage.clear()

        // Then: the folder is gone when `clear()` returns, and the temporary folder it moved into goes after
        XCTAssertFalse(fileManager.fileExists(atPath: try folder().path))
        XCTAssertNil(try storage.fetch(forKey: "key"))
        let temporaryFolder = try XCTUnwrap(backingStore.removedInBackground.first)
        XCTAssertFalse(temporaryFolder.path.hasPrefix(base.path))
        try await waitUntilGone(temporaryFolder)
    }

    func testASaveWhoseFolderIsClearedMidSaveSavesIntoANewOne() throws {
        // Given: a clear right before the next write, as another thread or process can make
        let backingStore = ObservedFileBackingStore()
        let storage = try FileStorage(scope: .own(namespace: "test"), backingStore: backingStore, locator: locator)
        try storage.save(Data([1]), forKey: "other")
        backingStore.beforeNextWrite = { try storage.clear() }

        // When
        try storage.save(Data([2]), forKey: "key")

        // Then: the first write failed in the moved folder, and the second one made a new folder
        XCTAssertEqual(try storage.fetch(forKey: "key"), Data([2]))
        XCTAssertNil(try storage.fetch(forKey: "other"))
        XCTAssertEqual(backingStore.writes, 3)
    }

    // MARK: Links

    func testALinkIsNeverAValueOrFollowed() throws {
        // Given: links with keys' names, to a file and to a folder
        let scopeFolder = try makeScopeFolder()
        let file = try makeFile("target")
        let folder = try makeFolder("folder")
        try makeLink("tofile", to: file, in: scopeFolder)
        try makeLink("tofolder", to: folder, in: scopeFolder)
        let storage = try storage()

        for key in ["tofile", "tofolder"] {
            // When
            let fetched = try storage.fetch(forKey: .init(key))
            let error = storageError { try storage.save(Data([2]), forKey: .init(key)) }
            try storage.delete(forKey: .init(key))

            // Then: `save` never replaces the link, and `delete` removes it, never what it points to
            XCTAssertNil(fetched, key)
            assertPathOccupied(error, scopeFolder.appendingPathComponent(key, isDirectory: false))
        }

        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: scopeFolder.path), [])
        XCTAssertEqual(try Data(contentsOf: file), Data([1]))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("inner").path))
    }

    func testALinkInTheScopesFoldersPlaceIsNeverFollowed() throws {
        // Given
        let target = try makeFolder("target")
        let scopeFolder = try folder()
        try makeLink(scopeFolder.lastPathComponent, to: target, in: makeFolder(scopeFolder.deletingLastPathComponent()))
        let storage = try storage()

        // When
        let fetched = try storage.fetch(forKey: "inner")
        try storage.delete(forKey: "inner")
        let error = storageError { try storage.save(Data([1]), forKey: "key") }

        // Then
        XCTAssertNil(fetched)
        assertPathOccupied(error, scopeFolder)
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: target.path), ["inner"])

        // When - Then: `clear()` takes the link out, never what it points to
        try storage.clear()
        XCTAssertFalse(fileManager.fileExists(atPath: scopeFolder.path))
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: target.path), ["inner"])
    }

    // MARK: Permissions

    func testPermissionErrorsAreReportedAndChangeNothing() throws {
        try XCTSkipIf(getuid() == 0, "File permissions are not enforced for root")

        // Given: a folder that can be listed and read, but not written
        let storage = try storage()
        try storage.save(Data([1]), forKey: "key")
        try setPermissions(0o555, of: folder())

        // When
        let errors = [
            storageError { try storage.save(Data([2]), forKey: "new") },
            storageError { try storage.save(Data([2]), forKey: "key") },
            storageError { try storage.delete(forKey: "key") },
            storageError { try storage.clear() }
        ]

        // Then: `clear()` couldn't move the folder, which moving needs to write to
        for error in errors {
            assertOther(error, posix: .EACCES)
        }

        XCTAssertEqual(try storage.fetch(forKey: "key"), Data([1]))
        XCTAssertNil(try storage.fetch(forKey: "new"))
    }

    func testAFolderThatCantBeLookedIntoIsNeverTakenForEmpty() throws {
        try XCTSkipIf(getuid() == 0, "File permissions are not enforced for root")

        // Given
        let storage = try storage()
        try storage.save(Data([1]), forKey: "key")
        try setPermissions(0o000, of: folder())

        // When
        let errors = [
            storageError { _ = try storage.fetch(forKey: "key") },
            storageError { try storage.delete(forKey: "key") },
            storageError { try storage.clear() }
        ]

        // Then
        for error in errors {
            assertOther(error, posix: .EACCES)
        }
    }

    func testAnUnreadableFileIsReportedButCanBeDeleted() throws {
        try XCTSkipIf(getuid() == 0, "File permissions are not enforced for root")

        // Given
        let storage = try storage()
        try storage.save(Data([1]), forKey: "key")
        try setPermissions(0o000, of: folder().appendingPathComponent("key"))

        // When
        let error = storageError { _ = try storage.fetch(forKey: "key") }
        try storage.delete(forKey: "key")

        // Then
        assertOther(error, posix: .EACCES)
        XCTAssertFalse(fileManager.fileExists(atPath: try folder().appendingPathComponent("key").path))
    }

    // MARK: Helpers

    private func storage(_ scope: FileStorage.Scope = .own(namespace: "test")) throws(FileStorage.Error) -> FileStorage {
        try FileStorage(scope: scope, backingStore: DefaultFileBackingStoreWrapper(), locator: locator)
    }

    private func folder(_ scope: FileStorage.Scope = .own(namespace: "test")) throws(FileStorage.Error) -> URL {
        try locator.directory(for: scope)
    }

    private func isExcludedFromBackup(_ url: URL) throws -> Bool? {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
    }

    private func protectionClass(of url: URL) throws -> FileProtectionType? {
        try fileManager.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType
    }

    /// Returns once nothing is at `url`, looking every 10 ms; fails the test after `timeout` seconds.
    private func waitUntilGone(_ url: URL, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while fileManager.fileExists(atPath: url.path) {
            guard Date() < deadline else {
                return XCTFail("\(url.path) is still there after \(timeout) s", file: file, line: line)
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// A folder in the test's base whose path is `length` bytes, in names of at most 200.
    private func deepFolder(length: Int) throws -> URL {
        var folder = base!
        while folder.path.utf8.count < length {
            folder.appendPathComponent(String(repeating: "d", count: min(200, length - folder.path.utf8.count - 1)), isDirectory: true)
        }

        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertEqual(folder.path.utf8.count, length)
        return folder
    }

    private func makeScopeFolder() throws -> URL {
        try makeFolder(folder())
    }

    @discardableResult
    private func makeFolder(_ url: URL) throws -> URL {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func makeFile(_ name: String, in folder: URL? = nil) throws -> URL {
        let url = (folder ?? base).appendingPathComponent(name, isDirectory: false)
        try Data([1]).write(to: url)
        return url
    }

    @discardableResult
    private func makeFolder(_ name: String, in folder: URL? = nil) throws -> URL {
        let url = try makeFolder((folder ?? base).appendingPathComponent(name, isDirectory: true))
        try Data([1]).write(to: url.appendingPathComponent("inner"))
        return url
    }

    @discardableResult
    private func makeLink(_ name: String, to destination: URL, in folder: URL? = nil) throws -> URL {
        let url = (folder ?? base).appendingPathComponent(name, isDirectory: false)
        try fileManager.createSymbolicLink(at: url, withDestinationURL: destination)
        return url
    }

    /// Changes permissions until the test ends, so the temporary folder can still be removed.
    private func setPermissions(_ permissions: Int, of url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    /// The error `body` throws; without the `FullTypedThrows` feature, Swift infers closures as throwing `any Error`.
    private func storageError(file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) -> FileStorage.Error? {
        do {
            try body()
            return nil
        } catch {
            guard let error = error as? FileStorage.Error else {
                XCTFail("Expected a FileStorage.Error, got \(error)", file: file, line: line)
                return nil
            }

            return error
        }
    }

    private func assertPathOccupied(_ error: FileStorage.Error?, _ url: URL, file: StaticString = #filePath, line: UInt = #line) {
        guard case let .pathOccupied(occupied)? = error else {
            return XCTFail("Expected .pathOccupied, got \(String(describing: error))", file: file, line: line)
        }

        XCTAssertEqual(occupied.standardizedFileURL.path, url.standardizedFileURL.path, file: file, line: line)
    }

    private func assertOther(_ error: FileStorage.Error?, posix: POSIXErrorCode, file: StaticString = #filePath, line: UInt = #line) {
        guard case let .other(underlying)? = error else {
            return XCTFail("Expected .other, got \(String(describing: error))", file: file, line: line)
        }

        XCTAssertEqual(posixCode(of: underlying), posix, file: file, line: line)
    }

    private func posixCode(of error: any Error) -> POSIXErrorCode? {
        if case let .other(code)? = error as? FileItemError {
            return POSIXErrorCode(rawValue: code)
        }

        let error = error as NSError
        let posix = error.domain == NSPOSIXErrorDomain ? error : error.userInfo[NSUnderlyingErrorKey] as? NSError
        return posix.flatMap { $0.domain == NSPOSIXErrorDomain ? POSIXErrorCode(rawValue: Int32($0.code)) : nil }
    }
}

/// The live file system, which counts writes, records what it removes in the background, and runs a call right before
/// the next write, as another thread or process can.
/// Unchecked: used from one test at a time.
private final class ObservedFileBackingStore: DefaultFileBackingStoreWrapper, @unchecked Sendable {
    var beforeNextWrite: (() throws -> Void)?
    private(set) var writes = 0
    private(set) var removedInBackground = [URL]()

    override func write(_ data: Data, at url: URL, options: Data.WritingOptions) throws {
        writes += 1
        if let beforeNextWrite {
            self.beforeNextWrite = nil
            try beforeNextWrite()
        }

        try super.write(data, at: url, options: options)
    }

    override func removeInBackground(at url: URL) {
        removedInBackground.append(url)
        super.removeInBackground(at: url)
    }
}

/// Counts what fetches found, from any thread.
private final class Fetches: @unchecked Sendable {
    private let lock = NSLock()
    private var counts = (found: 0, missing: 0)

    var found: Int {
        lock.withLock { counts.found }
    }

    var missing: Int {
        lock.withLock { counts.missing }
    }

    /// Whether the fetches found the file, and found none, `count` times each.
    func foundBoth(_ count: Int) -> Bool {
        lock.withLock { counts.found >= count && counts.missing >= count }
    }

    func record(_ value: Data?) {
        lock.withLock {
            if value == nil {
                counts.missing += 1
            } else {
                counts.found += 1
            }
        }
    }
}

/// Reads a file in a tight loop on its own thread, like another process would.
private final class ConcurrentReader: @unchecked Sendable {
    private let url: URL
    private let expectedValues: [Data]
    private let lock = NSLock()
    private let finished = DispatchSemaphore(value: 0)
    private var isRunning = true
    private var reads = 0
    private var missing = 0
    private var partial = 0

    init(url: URL, expectedValues: [Data]) {
        self.url = url
        self.expectedValues = expectedValues
    }

    func start() {
        Thread.detachNewThread { [self] in
            while running() {
                let data = try? Data(contentsOf: url)
                lock.lock()
                reads += 1
                if let data {
                    partial += expectedValues.contains(data) ? 0 : 1
                } else {
                    missing += 1
                }
                lock.unlock()
            }

            finished.signal()
        }
    }

    func stop() -> (reads: Int, missing: Int, partial: Int) {
        lock.lock()
        isRunning = false
        lock.unlock()
        finished.wait()

        lock.lock()
        defer { lock.unlock() }
        return (reads, missing, partial)
    }

    private func running() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }
}
