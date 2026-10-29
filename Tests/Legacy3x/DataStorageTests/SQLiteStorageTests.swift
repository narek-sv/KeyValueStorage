//
//  SQLiteStorageTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 15.10.26.
//

import XCTest
import Foundation
import Combine
import SQLite3
@testable import KeyValueStorage

final class SQLiteStorageTests: XCTestCase {
    static let otherStorageScope = "other"
    var fileManager = FileManager.default
    var standardStorage: SQLiteStorage!
    var otherStorage: SQLiteStorage!
    
    @SQLiteActor
    override func setUp() async throws {
        standardStorage = try SQLiteStorage()
        otherStorage = try SQLiteStorage(scope: Self.otherStorageScope)
        try standardStorage.clear()
        try otherStorage.clear()
    }
    
    // XCTest keeps every test case alive until the run ends, so close the connections now
    // instead of running out of file descriptors when tests are repeated
    @SQLiteActor
    override func tearDown() async throws {
        standardStorage = nil
        otherStorage = nil
    }
    
    @SQLiteActor
    func testSQLiteScope() async {
        XCTAssertEqual(standardStorage.scope, nil)
        XCTAssertEqual(otherStorage.scope, Self.otherStorageScope)
    }
    
    @SQLiteActor
    func testSQLiteFetch() async throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        
        // When
        var fetched1 = try standardStorage.fetch(forKey: "key1")
        var fetched2 = try standardStorage.fetch(forKey: "key2")
        
        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
        
        // When
        try standardStorage.save(data1, forKey: "key1")
        try standardStorage.save(data2, forKey: "key2")
        fetched1 = try standardStorage.fetch(forKey: "key1")
        fetched2 = try standardStorage.fetch(forKey: "key2")
        
        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertEqual(fetched2, data2)
    }
    
    @SQLiteActor
    func testSQLiteSave() async throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        
        // When
        try standardStorage.save(data1, forKey: "key")
        try standardStorage.save(data2, forKey: "key")
        try standardStorage.save(data2, forKey: "key")
        
        // Then
        XCTAssertEqual(try standardStorage.fetch(forKey: "key"), data2)
        XCTAssertNil(try standardStorage.fetch(forKey: "other"))
    }
    
    @SQLiteActor
    func testSQLiteDelete() async throws {
        // Given
        let data = Data([0xAA, 0xBB, 0xCC])
        try standardStorage.save(data, forKey: "key1")
        try standardStorage.save(data, forKey: "key2")
        
        // When
        try standardStorage.delete(forKey: "key1")
        try standardStorage.delete(forKey: "key1")
        try standardStorage.delete(forKey: "missing")
        
        // Then
        XCTAssertNil(try standardStorage.fetch(forKey: "key1"))
        XCTAssertEqual(try standardStorage.fetch(forKey: "key2"), data)
    }
    
    @SQLiteActor
    func testSQLiteSet() async throws {
        // Given
        let data = Data([0xAA, 0xBB, 0xCC])
        
        // When
        try standardStorage.set(data, forKey: "key")
        
        // Then
        XCTAssertEqual(try standardStorage.fetch(forKey: "key"), data)
        
        // When
        try standardStorage.set(nil, forKey: "key")
        try standardStorage.set(nil, forKey: "missing")
        
        // Then
        XCTAssertNil(try standardStorage.fetch(forKey: "key"))
    }
    
    @SQLiteActor
    func testSQLiteDifferentScopes() async throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        
        // When
        try standardStorage.save(data1, forKey: "key")
        try otherStorage.save(data2, forKey: "key")
        
        // Then
        XCTAssertEqual(try standardStorage.fetch(forKey: "key"), data1)
        XCTAssertEqual(try otherStorage.fetch(forKey: "key"), data2)
        
        // When
        try standardStorage.delete(forKey: "key")
        
        // Then
        XCTAssertNil(try standardStorage.fetch(forKey: "key"))
        XCTAssertEqual(try otherStorage.fetch(forKey: "key"), data2)
    }
    
    @SQLiteActor
    func testSQLiteClear() async throws {
        // Given
        let data = Data([0xAA, 0xBB, 0xCC])
        try standardStorage.save(data, forKey: "key1")
        try standardStorage.save(data, forKey: "key2")
        try otherStorage.save(data, forKey: "key1")
        
        // When
        try standardStorage.clear()
        
        // Then
        XCTAssertNil(try standardStorage.fetch(forKey: "key1"))
        XCTAssertNil(try standardStorage.fetch(forKey: "key2"))
        XCTAssertEqual(try otherStorage.fetch(forKey: "key1"), data)
        
        // When
        try standardStorage.save(data, forKey: "key1")
        
        // Then
        XCTAssertEqual(try standardStorage.fetch(forKey: "key1"), data)
    }
    
    @SQLiteActor
    func testDefaultLocation() async throws {
        // Given
        let expectedPath = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier!)
            .appendingPathComponent("KeyValueStorage")
            .appendingPathComponent(SQLiteStorage.directoryName)
            .appendingPathComponent(SQLiteStorage.databaseName)
            .path
        
        // When
        try standardStorage.save(Data([0xAA]), forKey: "key")
        
        // Then
        XCTAssertEqual(SQLiteStorage.directoryName, "SQLite")
        XCTAssertEqual(SQLiteStorage.databaseName, "KeyValueStorage.sqlite")
        XCTAssertTrue(fileManager.fileExists(atPath: expectedPath))
    }
    
    @SQLiteActor
    func testSharedLocationDoesNotDependOnBundleIdentifier() async throws {
        // Given
        let expectedPath = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.otherStorageScope)!
            .appendingPathComponent("KeyValueStorage")
            .appendingPathComponent(SQLiteStorage.directoryName)
            .appendingPathComponent(SQLiteStorage.databaseName)
            .path
        
        // When
        try otherStorage.save(Data([0xAA]), forKey: "key")
        let sameScopeStorage = try SQLiteStorage(scope: Self.otherStorageScope)
        
        // Then
        XCTAssertTrue(fileManager.fileExists(atPath: expectedPath))
        XCTAssertFalse(expectedPath.contains(Bundle.main.bundleIdentifier!))
        XCTAssertEqual(try sameScopeStorage.fetch(forKey: "key"), Data([0xAA]))
    }
    
    @SQLiteActor
    func testFileStorageAndSQLiteStorageDontAffectEachOther() async throws {
        // Given
        let fileStorage = try await FileStorage()
        let sharedFileStorage = try await FileStorage(scope: Self.otherStorageScope)
        try standardStorage.save(Data([0xAA]), forKey: "key")
        try otherStorage.save(Data([0xAA]), forKey: "key")
        try await fileStorage.save(Data([0xBB]), forKey: "key")
        try await sharedFileStorage.save(Data([0xBB]), forKey: "key")
        
        // When
        try await fileStorage.clear()
        try await sharedFileStorage.clear()
        
        // Then
        XCTAssertEqual(try standardStorage.fetch(forKey: "key"), Data([0xAA]))
        XCTAssertEqual(try otherStorage.fetch(forKey: "key"), Data([0xAA]))
        
        // When
        try await fileStorage.save(Data([0xBB]), forKey: "key")
        try await sharedFileStorage.save(Data([0xBB]), forKey: "key")
        try standardStorage.clear()
        try otherStorage.clear()
        
        // Then
        let file = try await fileStorage.fetch(forKey: "key")
        let sharedFile = try await sharedFileStorage.fetch(forKey: "key")
        XCTAssertEqual(file, Data([0xBB]))
        XCTAssertEqual(sharedFile, Data([0xBB]))
        
        try await fileStorage.clear()
        try await sharedFileStorage.clear()
    }
    
    @SQLiteActor
    func testValuesPersistAcrossInstances() async throws {
        // Given
        let root = makeTemporaryRoot()
        var storage: SQLiteStorage? = try SQLiteStorage(fileManager: fileManager, root: root)
        try storage?.save(Data([0xAA]), forKey: "key")
        
        // When
        storage = nil
        let reopened = try SQLiteStorage(fileManager: fileManager, root: root)
        
        // Then
        XCTAssertEqual(try reopened.fetch(forKey: "key"), Data([0xAA]))
        XCTAssertNil(reopened.scope)
    }
    
    @SQLiteActor
    func testInstancesSharingDatabaseSeeEachOthersChanges() async throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let root = makeTemporaryRoot()
        let first = try SQLiteStorage(fileManager: fileManager, root: root)
        let second = try SQLiteStorage(fileManager: fileManager, root: root)
        
        // When
        try first.save(data1, forKey: "key")
        
        // Then
        XCTAssertEqual(try second.fetch(forKey: "key"), data1)
        
        // When
        try second.save(data2, forKey: "key")
        
        // Then
        XCTAssertEqual(try first.fetch(forKey: "key"), data2)
        
        // When
        try first.save(data1, forKey: "other")
        try second.clear()
        
        // Then
        XCTAssertNil(try first.fetch(forKey: "key"))
        XCTAssertNil(try first.fetch(forKey: "other"))
    }
    
    @SQLiteActor
    func testValueRoundTrips() async throws {
        // Given
        let values = [
            Data(),
            Data((0...255).map { UInt8($0) }),
            Data((0..<1_048_576).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        ]
        
        for value in values {
            // When
            try standardStorage.save(value, forKey: "key")
            
            // Then
            XCTAssertEqual(try standardStorage.fetch(forKey: "key"), value)
        }
        
        // When
        try standardStorage.save(Data(), forKey: "empty")
        
        // Then
        XCTAssertNotNil(try standardStorage.fetch(forKey: "empty"))
    }
    
    @SQLiteActor
    func testAnyKeyIsValid() async throws {
        // Given
        let keys = ["", ".", "..", "../escaped", "a/b", "a\0b", "a", "Key", "key", "ключ 🔑", String(repeating: "ж", count: 10_000)]
        
        for (index, key) in keys.enumerated() {
            // When
            try standardStorage.save(Data([UInt8(index)]), forKey: key)
        }
        
        for (index, key) in keys.enumerated() {
            // Then
            XCTAssertEqual(try standardStorage.fetch(forKey: key), Data([UInt8(index)]), "key \(key.debugDescription)")
        }
    }
    
    func testUnifiedStorage() async throws {
        // Given
        let storage = UnifiedStorage(factory: ObservableUnifiedStorageFactory())
        let key = SQLiteKey<String>(key: "unified")
        let sharedKey = SQLiteKey<Int>(key: "unified", scope: Self.otherStorageScope)
        let values = Recorded<String?>()
        let subscription = try await storage.publisher(forKey: key)!.sink { values.append($0) }
        
        // When
        try await storage.save("value", forKey: key)
        try await storage.save(42, forKey: sharedKey)
        
        // Then
        let fetched = try await storage.fetch(forKey: key)
        let fetchedShared = try await storage.fetch(forKey: sharedKey)
        XCTAssertEqual(fetched, "value")
        XCTAssertEqual(fetchedShared, 42)
        XCTAssertEqual(values.all, [nil, "value"])
        
        // When
        try await storage.delete(forKey: key)
        try await storage.clear(storage: SQLiteStorage.self, forScope: Self.otherStorageScope)
        
        // Then
        let deleted = try await storage.fetch(forKey: key)
        let cleared = try await storage.fetch(forKey: sharedKey)
        XCTAssertNil(deleted)
        XCTAssertNil(cleared)
        subscription.cancel()
    }
    
    @SQLiteActor
    func testErrorCaseRootIsAFile() async throws {
        // Given
        let file = try makeTemporaryFile()
        
        // When
        XCTAssertThrowsError(try SQLiteStorage(fileManager: fileManager, root: file)) { error in
            // Then
            guard case .other = error as? SQLiteStorage.Error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
    }
    
    @SQLiteActor
    func testErrorCaseCorruptDatabase() async throws {
        // Given
        let root = makeTemporaryRoot()
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 0x2A, count: 4096).write(to: root.appendingPathComponent(SQLiteStorage.databaseName))
        
        // When
        XCTAssertThrowsError(try SQLiteStorage(fileManager: fileManager, root: root)) { error in
            // Then
            guard case let .sqlite(code, message) = error as? SQLiteStorage.Error else {
                return XCTFail("Unexpected error \(error)")
            }
            
            XCTAssertEqual(code, SQLITE_NOTADB)
            XCTAssertFalse(message.isEmpty)
        }
    }
    
    @SQLiteActor
    func testErrorCaseDatabaseIsADirectory() async throws {
        // Given
        let root = makeTemporaryRoot()
        try fileManager.createDirectory(at: root.appendingPathComponent(SQLiteStorage.databaseName), withIntermediateDirectories: true)
        
        // When
        XCTAssertThrowsError(try SQLiteStorage(fileManager: fileManager, root: root)) { error in
            // Then
            assertSQLiteError(error, SQLITE_CANTOPEN)
        }
    }
    
    @SQLiteActor
    func testErrorCaseDatabaseLockedByAnotherConnection() async throws {
        // Given
        let root = makeTemporaryRoot()
        let storage = try SQLiteStorage(fileManager: fileManager, root: root)
        try storage.save(Data([0xAA]), forKey: "key")
        let other = try openConnection(root: root)
        defer { sqlite3_close_v2(other) }
        XCTAssertEqual(sqlite3_exec(other, "BEGIN EXCLUSIVE", nil, nil, nil), SQLITE_OK)
        
        // When
        let start = Date()
        XCTAssertThrowsError(try storage.save(Data([0xBB]), forKey: "key")) { error in
            // Then: the save waits for the busy timeout before failing, like during another process's long write
            assertSQLiteError(error, SQLITE_BUSY)
        }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.9)
        XCTAssertEqual(try storage.fetch(forKey: "key"), Data([0xAA]), "Readers don't wait for the writer in WAL mode")
        
        // When
        XCTAssertEqual(sqlite3_exec(other, "ROLLBACK", nil, nil, nil), SQLITE_OK)
        try storage.save(Data([0xBB]), forKey: "key")
        
        // Then
        XCTAssertEqual(try storage.fetch(forKey: "key"), Data([0xBB]))
    }
    
    @SQLiteActor
    func testErrorCaseTableRemoved() async throws {
        // Given
        let root = makeTemporaryRoot()
        let storage = try SQLiteStorage(fileManager: fileManager, root: root)
        try storage.save(Data([0xAA]), forKey: "key")
        let other = try openConnection(root: root)
        defer { sqlite3_close_v2(other) }
        XCTAssertEqual(sqlite3_exec(other, "DROP TABLE KeyValueStorage", nil, nil, nil), SQLITE_OK)
        
        // When - Then
        XCTAssertThrowsError(try storage.fetch(forKey: "key")) { assertSQLiteError($0, SQLITE_ERROR) }
        XCTAssertThrowsError(try storage.save(Data([0xBB]), forKey: "key")) { assertSQLiteError($0, SQLITE_ERROR) }
        XCTAssertThrowsError(try storage.delete(forKey: "key")) { assertSQLiteError($0, SQLITE_ERROR) }
        XCTAssertThrowsError(try storage.clear()) { assertSQLiteError($0, SQLITE_ERROR) }
        
        // When
        let reopened = try SQLiteStorage(fileManager: fileManager, root: root)
        try reopened.save(Data([0xBB]), forKey: "key")
        
        // Then: opening the database creates the table again
        XCTAssertEqual(try reopened.fetch(forKey: "key"), Data([0xBB]))
    }
    
    func testThreadSafety() async throws {
        // Given
        let storage = standardStorage!
        let iterations = 5000
        
        // When
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 1...iterations {
                let operation = Int.random(in: 0...4)
                let key = "\(Int.random(in: 1000...9999))"
                
                // Child tasks run in parallel on the shared thread pool, so the storage is called from many threads at once
                group.addTask {
                    switch operation {
                    case 0:
                        _ = try await storage.fetch(forKey: key)
                    case 1:
                        try await storage.save(.init(), forKey: key)
                    case 2:
                        try await storage.delete(forKey: key)
                    case 3:
                        try await storage.set(Bool.random() ? nil : .init(), forKey: key)
                    case 4:
                        try await storage.clear()
                    default:
                        break
                    }
                }
            }
            
            // Then: waiting for all of them rethrows the first error, instead of a timeout guessing how long they take
            try await group.waitForAll()
        }
    }
    
    // MARK: Helpers
    
    /// A second connection to the storage's database, like another process would open.
    private func openConnection(root: URL) throws -> OpaquePointer {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(root.appendingPathComponent(SQLiteStorage.databaseName).path, &database, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        return try XCTUnwrap(database)
    }
    
    private func assertSQLiteError(_ error: Error, _ expectedCode: Int32, line: UInt = #line) {
        guard case let .sqlite(code, message) = error as? SQLiteStorage.Error else {
            return XCTFail("Unexpected error \(error)", line: line)
        }
        
        XCTAssertEqual(code, expectedCode, message, line: line)
        XCTAssertFalse(message.isEmpty, line: line)
    }
    
    /// A not yet created directory, removed after the test.
    private func makeTemporaryRoot() -> URL {
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        // FileManager isn't Sendable, so the block can't capture it
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        
        return root
    }
    
    /// An empty file, removed after the test.
    private func makeTemporaryFile() throws -> URL {
        let file = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: file)
        }
        
        return file
    }
}

/// Collects values delivered on any thread.
private final class Recorded<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values = [Value]()
    
    var all: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
    
    func append(_ value: Value) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }
}
