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
        XCTAssertEqual(locator.ownIdentifier, OwnIdentity.identifier)
    }

    // MARK: Values

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
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: folder().path), [])
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

    // MARK: Clashes

    func testScopesThatDifferOnlyInRetentionProtectionOrGroupKeepTheirValuesApart() throws {
        // Given: one namespace in every kind of place
        let scopes: [FileStorage.Scope] = [
            .own(namespace: "name"), .own(.cache, namespace: "name"), .own(.temporary, namespace: "name"),
            .own(protection: .none, namespace: "name"), .appGroup(id: "group.test", namespace: "name")
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

    func testAFolderAtAKeysPathIsNeverAValueAndNeverRemoved() throws {
        // Given: another app's folder with a key's name
        let storage = try storage()
        let folder = try makeFolder("settings", in: makeScopeFolder())

        // When
        let fetched = try storage.fetch(forKey: "settings")
        try storage.delete(forKey: "settings")
        try storage.clear()
        let error = storageError { try storage.save(Data([2]), forKey: "settings") }

        // Then
        XCTAssertNil(fetched)
        assertPathOccupied(error, folder)
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("inner").path))
    }

    func testAFileWhereTheScopesFolderGoesIsNeverAValueAndNeverRemoved() throws {
        // Given
        let storage = try storage()
        let scopeFolder = try folder()
        let file = try makeFile(scopeFolder.lastPathComponent, in: makeFolder(scopeFolder.deletingLastPathComponent()))

        // When
        let fetched = try storage.fetch(forKey: "key")
        try storage.delete(forKey: "key")
        try storage.clear()
        let error = storageError { try storage.save(Data([2]), forKey: "key") }

        // Then
        XCTAssertNil(fetched)
        assertPathOccupied(error, scopeFolder)
        XCTAssertEqual(try Data(contentsOf: file), Data([1]))
    }

    func testClearRemovesExactlyTheScopesValues() throws {
        // Given: two namespaces, with SQLite's database and other code's files in the first one's folder
        let first = try storage(.own(namespace: "first"))
        let second = try storage(.own(namespace: "second"))
        try first.save(Data([1]), forKey: "key")
        try first.save(Data([1]), forKey: "Key")
        try second.save(Data([2]), forKey: "key")
        let folder = try folder(.own(namespace: "first"))
        let sqlite = try SQLiteStorage(scope: .own(namespace: "first"), backingStore: DefaultSQLiteBackingStoreWrapper(), locator: TestSQLiteLocator(base: base))
        try sqlite.save(Data([3]), forKey: "key")
        try makeFile(".hidden", in: folder)
        try makeFile("Notes.txt", in: folder)   // no key produces a raw capital or `.`
        try makeFile("todo", in: folder)        // a key could have written it

        // When
        try first.clear()

        // Then
        XCTAssertNil(try first.fetch(forKey: "key"))
        XCTAssertNil(try first.fetch(forKey: "Key"))
        XCTAssertEqual(try second.fetch(forKey: "key"), Data([2]))
        XCTAssertEqual(try sqlite.fetch(forKey: "key"), Data([3]))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent(".hidden").path))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("Notes.txt").path))
        XCTAssertFalse(fileManager.fileExists(atPath: folder.appendingPathComponent("todo").path))
    }

    // MARK: Links

    func testALinkIsNeverAValueAndNeverTouched() throws {
        // Given: links with keys' names, to a file and to a folder
        let scopeFolder = try makeScopeFolder()
        let file = try makeFile("target", in: scopeFolder)
        let folder = try makeFolder("folder", in: scopeFolder)
        try makeLink("tofile", to: file, in: scopeFolder)
        try makeLink("tofolder", to: folder, in: scopeFolder)
        let storage = try storage()

        for key in ["tofile", "tofolder"] {
            // When
            let fetched = try storage.fetch(forKey: .init(key))
            try storage.delete(forKey: .init(key))
            let error = storageError { try storage.save(Data([2]), forKey: .init(key)) }

            // Then
            XCTAssertNil(fetched, key)
            assertPathOccupied(error, scopeFolder.appendingPathComponent(key, isDirectory: false))
        }

        // When
        try storage.clear()

        // Then: both links stay, and so does what they point to, apart from `target`, a key's file
        XCTAssertEqual(Set(try fileManager.contentsOfDirectory(atPath: scopeFolder.path)), ["folder", "tofile", "tofolder"])
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("inner").path))
    }

    func testALinkInTheScopesFoldersPlaceIsNeverFollowed() throws {
        // Given
        let target = try makeFolder(base.appendingPathComponent("target", isDirectory: true))
        let scopeFolder = try folder()
        try makeLink(scopeFolder.lastPathComponent, to: target, in: makeFolder(scopeFolder.deletingLastPathComponent()))
        let storage = try storage()

        // When
        let error = storageError { try storage.save(Data([1]), forKey: "key") }

        // Then
        assertPathOccupied(error, scopeFolder)
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: target.path), [])
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

    /// The default scope's folder, made ahead of the storage.
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
