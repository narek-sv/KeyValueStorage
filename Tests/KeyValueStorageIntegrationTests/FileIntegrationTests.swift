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

    override func setUpWithError() throws {
        let base = fileManager.temporaryDirectory.appendingPathComponent("FileIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        self.base = base
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
        XCTAssertEqual(Set(try adapter.itemNames(at: base)), ["file", "folder", "linkToFile", "linkToFolder"])
    }

    /// `FileStorage` takes `fileReadNoSuchFile` from `itemType` for "nothing is there", and every other error for an error.
    func testOnlyAMissingItemIsNoSuchFile() throws {
        // Given
        let adapter = DefaultFileBackingStoreWrapper()
        let underFile = try makeFile("file").appendingPathComponent("key")

        // When - Then
        XCTAssertThrowsError(try adapter.itemType(at: base.appendingPathComponent("missing"))) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileReadNoSuchFile)
        }

        XCTAssertThrowsError(try adapter.itemType(at: underFile)) { error in
            XCTAssertNotEqual((error as? CocoaError)?.code, .fileReadNoSuchFile)
        }

        try XCTSkipIf(getuid() == 0, "File permissions are not enforced for root")
        let locked = try makeFolder("locked")
        try setPermissions(0o000, of: locked)
        XCTAssertThrowsError(try adapter.itemType(at: locked.appendingPathComponent("inner"))) { error in
            XCTAssertNotEqual((error as? CocoaError)?.code, .fileReadNoSuchFile)
        }
    }

    func testTheLocatorsLookupsReturnTheSystemsDirectories() {
        let locator = DefaultFileLocator()

        XCTAssertEqual(locator.temporaryDirectory, fileManager.temporaryDirectory)
        XCTAssertEqual(locator.systemDirectory(.applicationSupportDirectory), fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        XCTAssertEqual(locator.systemDirectory(.cachesDirectory), fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first)
        // Outside a sandbox, macOS returns a container for any group ID
        let groupId = "group.not.entitled.\(UUID().uuidString)"
        XCTAssertEqual(locator.groupDirectory(for: groupId), fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupId))
    }

    // MARK: Values

    func testValuesRoundTripInFilesNamedAfterTheirKeys() throws {
        // Given
        let storage = try FileStorage(scope: .app(.directory(at: base), namespace: .directory(named: "values")))
        let folder = base.appendingPathComponent("values!", isDirectory: true)

        // When
        try storage.save(Data([1]), forKey: "key")
        try storage.save(Data([2]), forKey: "Key")
        try storage.save(Data([3]), forKey: "\u{E9}")
        try storage.save(Data([4]), forKey: "e\u{301}")

        // Then: keys that differ only in case, and the two spellings of `é`, have files of their own
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
        let storage = try FileStorage(scope: .app(.directory(at: base)))
        let characters = (0x20...0x7E).map { String(UnicodeScalar(UInt8($0))) }
        let keys = [""] + characters + characters.flatMap { first in characters.map { first + $0 } }

        // When
        for key in keys {
            try storage.save(Data(key.utf8), forKey: .init(name: key))
        }

        // Then
        for key in keys {
            XCTAssertEqual(try storage.fetch(forKey: .init(name: key)), Data(key.utf8), key.debugDescription)
        }

        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: base.path).count, keys.count)
        try storage.clear()
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: base.path), [])
    }

    func testOnlySavesCreateTheFolder() throws {
        // Given
        let storage = try FileStorage(scope: .app(.directory(at: base), namespace: .directory(named: "lazy")))
        let folder = base.appendingPathComponent("lazy!", isDirectory: true)

        // When
        XCTAssertNil(try storage.fetch(forKey: "key"))
        try storage.delete(forKey: "key")
        try storage.clear()

        // Then
        XCTAssertFalse(fileManager.fileExists(atPath: folder.path))

        // When
        try storage.save(Data([1]), forKey: "key")

        // Then
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("key").path))
    }

    func testInstancesSharingAFolderSeeEachOthersChanges() throws {
        // Given
        let first = try FileStorage(scope: .app(.directory(at: base)))
        let second = try FileStorage(scope: .app(.directory(at: base)))

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
        let storage = try FileStorage(scope: .app(.directory(at: base)))
        let values = [Data(repeating: 0x01, count: 64 * 1024), Data(repeating: 0x02, count: 256 * 1024)]
        try storage.save(values[0], forKey: "key")
        let reader = ConcurrentReader(url: base.appendingPathComponent("key"), expectedValues: values)

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

    // MARK: Clashes

    func testARootKeyAndANamespaceWithTheSameNameCoexist() throws {
        // Given
        let root = try FileStorage(scope: .app(.directory(at: base)))
        let namespaced = try FileStorage(scope: .app(.directory(at: base), namespace: .directory(named: "settings")))

        // When
        try root.save(Data([1]), forKey: "settings")
        try namespaced.save(Data([2]), forKey: "settings")
        try root.clear()

        // Then
        XCTAssertNil(try root.fetch(forKey: "settings"))
        XCTAssertEqual(try namespaced.fetch(forKey: "settings"), Data([2]))
    }

    func testAFolderAtAKeysPathIsNeverAValueAndNeverRemoved() throws {
        // Given: another app's folder with a key's name
        let folder = try makeFolder("settings")
        let root = try FileStorage(scope: .app(.directory(at: base)))

        // When
        let fetched = try root.fetch(forKey: "settings")
        try root.delete(forKey: "settings")
        try root.clear()
        let error = storageError { try root.save(Data([2]), forKey: "settings") }

        // Then
        XCTAssertNil(fetched)
        assertPathOccupied(error, base.appendingPathComponent("settings", isDirectory: false))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("inner").path))
    }

    func testAFileWhereTheScopesFolderGoesIsNeverAValueAndNeverRemoved() throws {
        // Given
        let file = try makeFile("blocked!")
        let storage = try FileStorage(scope: .app(.directory(at: base), namespace: .directory(named: "blocked")))

        // When
        let fetched = try storage.fetch(forKey: "key")
        try storage.delete(forKey: "key")
        try storage.clear()
        let error = storageError { try storage.save(Data([2]), forKey: "key") }

        // Then
        XCTAssertNil(fetched)
        assertPathOccupied(error, base.appendingPathComponent("blocked!", isDirectory: true))
        XCTAssertEqual(try Data(contentsOf: file), Data([1]))
    }

    func testClearRemovesExactlyTheScopesValues() throws {
        // Given: the root and a namespace of both file and SQLite storages in one folder, with foreign files
        let root = try FileStorage(scope: .app(.directory(at: base)))
        let namespaced = try FileStorage(scope: .app(.directory(at: base), namespace: .directory(named: "name")))
        let sqliteRoot = try SQLiteStorage(scope: .app(.directory(at: base)))
        let sqliteNamespaced = try SQLiteStorage(scope: .app(.directory(at: base), namespace: .directory(named: "name")))
        try root.save(Data([1]), forKey: "key")
        try root.save(Data([1]), forKey: "Key")
        try namespaced.save(Data([2]), forKey: "key")
        try sqliteRoot.save(Data([3]), forKey: "key")
        try sqliteNamespaced.save(Data([4]), forKey: "key")
        try makeFile(".hidden")
        try makeFile("Notes.txt")   // no key produces a raw capital or `.`
        try makeFile("todo")        // a key could: documented, a root in a shared folder claims it

        // When
        try root.clear()

        // Then
        XCTAssertNil(try root.fetch(forKey: "key"))
        XCTAssertNil(try root.fetch(forKey: "Key"))
        XCTAssertEqual(try namespaced.fetch(forKey: "key"), Data([2]))
        XCTAssertEqual(try sqliteRoot.fetch(forKey: "key"), Data([3]))
        XCTAssertEqual(try sqliteNamespaced.fetch(forKey: "key"), Data([4]))
        XCTAssertTrue(fileManager.fileExists(atPath: base.appendingPathComponent(".hidden").path))
        XCTAssertTrue(fileManager.fileExists(atPath: base.appendingPathComponent("Notes.txt").path))
        XCTAssertFalse(fileManager.fileExists(atPath: base.appendingPathComponent("todo").path))

        // When
        try root.save(Data([1]), forKey: "key")
        try namespaced.clear()

        // Then
        XCTAssertNil(try namespaced.fetch(forKey: "key"))
        XCTAssertEqual(try root.fetch(forKey: "key"), Data([1]))
        XCTAssertEqual(try sqliteNamespaced.fetch(forKey: "key"), Data([4]))
    }

    // MARK: Links

    func testALinkIsNeverAValueAndNeverTouched() throws {
        // Given: links with keys' names, to a file and to a folder
        let file = try makeFile("target")
        let folder = try makeFolder("folder")
        try makeLink("tofile", to: file)
        try makeLink("tofolder", to: folder)
        let storage = try FileStorage(scope: .app(.directory(at: base)))

        for key in ["tofile", "tofolder"] {
            // When
            let fetched = try storage.fetch(forKey: .init(name: key))
            try storage.delete(forKey: .init(name: key))
            let error = storageError { try storage.save(Data([2]), forKey: .init(name: key)) }

            // Then
            XCTAssertNil(fetched, key)
            assertPathOccupied(error, base.appendingPathComponent(key, isDirectory: false))
        }

        // When
        try storage.clear()

        // Then: both links stay, and so does what they point to, apart from `target`, a key's file
        XCTAssertEqual(Set(try fileManager.contentsOfDirectory(atPath: base.path)), ["folder", "tofile", "tofolder"])
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("inner").path))
    }

    func testALinkInTheScopesFoldersPlaceIsNeverFollowed() throws {
        // Given
        let folder = base.appendingPathComponent("target", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let storage = try FileStorage(scope: .app(.directory(at: makeLink("link", to: folder))))

        // When
        let error = storageError { try storage.save(Data([1]), forKey: "key") }

        // Then
        assertPathOccupied(error, base.appendingPathComponent("link", isDirectory: true))
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: folder.path), [])
    }

    // MARK: Permissions

    func testPermissionErrorsAreReportedAndChangeNothing() throws {
        try XCTSkipIf(getuid() == 0, "File permissions are not enforced for root")

        // Given: a folder that can be listed and read, but not written
        let storage = try FileStorage(scope: .app(.directory(at: base), namespace: .directory(named: "readonly")))
        let folder = base.appendingPathComponent("readonly!", isDirectory: true)
        try storage.save(Data([1]), forKey: "key")
        try setPermissions(0o555, of: folder)

        // When
        let errors = [
            storageError { try storage.save(Data([2]), forKey: "new") },
            storageError { try storage.save(Data([2]), forKey: "key") },
            storageError { try storage.delete(forKey: "key") },
            storageError { try storage.clear() }
        ]

        // Then
        for error in errors {
            assertOther(error, posix: .EACCES)
        }

        XCTAssertEqual(try storage.fetch(forKey: "key"), Data([1]))
        XCTAssertNil(try storage.fetch(forKey: "new"))
    }

    func testAFolderThatCantBeLookedIntoIsNeverTakenForEmpty() throws {
        try XCTSkipIf(getuid() == 0, "File permissions are not enforced for root")

        // Given
        let storage = try FileStorage(scope: .app(.directory(at: base), namespace: .directory(named: "locked")))
        try storage.save(Data([1]), forKey: "key")
        try setPermissions(0o000, of: base.appendingPathComponent("locked!", isDirectory: true))

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
        let storage = try FileStorage(scope: .app(.directory(at: base)))
        try storage.save(Data([1]), forKey: "key")
        try setPermissions(0o000, of: base.appendingPathComponent("key"))

        // When
        let error = storageError { _ = try storage.fetch(forKey: "key") }
        try storage.delete(forKey: "key")

        // Then
        assertOther(error, posix: .EACCES)
        XCTAssertFalse(fileManager.fileExists(atPath: base.appendingPathComponent("key").path))
    }

    // MARK: Helpers

    @discardableResult
    private func makeFile(_ name: String) throws -> URL {
        let url = base.appendingPathComponent(name, isDirectory: false)
        try Data([1]).write(to: url)
        return url
    }

    @discardableResult
    private func makeFolder(_ name: String) throws -> URL {
        let url = base.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try Data([1]).write(to: url.appendingPathComponent("inner"))
        return url
    }

    @discardableResult
    private func makeLink(_ name: String, to destination: URL) throws -> URL {
        let url = base.appendingPathComponent(name, isDirectory: false)
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
        let error = error as NSError
        let posix = error.domain == NSPOSIXErrorDomain ? error : error.userInfo[NSUnderlyingErrorKey] as? NSError
        return posix.flatMap { $0.domain == NSPOSIXErrorDomain ? POSIXErrorCode(rawValue: Int32($0.code)) : nil }
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
