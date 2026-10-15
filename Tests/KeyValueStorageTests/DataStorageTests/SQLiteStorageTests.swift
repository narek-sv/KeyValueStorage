//
//  SQLiteStorageTests.swift
//
//
//  Created by Narek Sahakyan on 15.10.26.
//

import XCTest
import Foundation
import Combine
import SQLite3
@testable import KeyValueStorage

final class SQLiteStorageTests: XCTestCase {
    static let otherStorageDomain = "other"
    var fileManager = FileManager.default
    var standardStorage: SQLiteStorage!
    var otherStorage: SQLiteStorage!
    
    @SQLiteActor
    override func setUpWithError() throws {
        standardStorage = try SQLiteStorage()
        otherStorage = try SQLiteStorage(domain: Self.otherStorageDomain)
        try standardStorage.clear()
        try otherStorage.clear()
    }
    
    @SQLiteActor
    func testSQLiteDomain() {
        XCTAssertEqual(standardStorage.domain, nil)
        XCTAssertEqual(otherStorage.domain, Self.otherStorageDomain)
    }
    
    @SQLiteActor
    func testSQLiteFetch() throws {
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
    func testSQLiteSave() throws {
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
    func testSQLiteDelete() throws {
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
    func testSQLiteSet() throws {
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
    func testSQLiteDifferentDomains() throws {
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
    func testSQLiteClear() throws {
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
    func testDefaultLocation() throws {
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
    func testSharedLocationDoesNotDependOnBundleIdentifier() throws {
        // Given
        let expectedPath = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.otherStorageDomain)!
            .appendingPathComponent("KeyValueStorage")
            .appendingPathComponent(SQLiteStorage.directoryName)
            .appendingPathComponent(SQLiteStorage.databaseName)
            .path
        
        // When
        try otherStorage.save(Data([0xAA]), forKey: "key")
        let sameDomainStorage = try SQLiteStorage(domain: Self.otherStorageDomain)
        
        // Then
        XCTAssertTrue(fileManager.fileExists(atPath: expectedPath))
        XCTAssertFalse(expectedPath.contains(Bundle.main.bundleIdentifier!))
        XCTAssertEqual(try sameDomainStorage.fetch(forKey: "key"), Data([0xAA]))
    }
    
    @SQLiteActor
    func testFileStorageAndSQLiteStorageDontAffectEachOther() async throws {
        // Given
        let fileStorage = try await FileStorage()
        let sharedFileStorage = try await FileStorage(domain: Self.otherStorageDomain)
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
    func testValuesPersistAcrossInstances() throws {
        // Given
        let root = makeTemporaryRoot()
        var storage: SQLiteStorage? = try SQLiteStorage(fileManager: fileManager, root: root)
        try storage?.save(Data([0xAA]), forKey: "key")
        
        // When
        storage = nil
        let reopened = try SQLiteStorage(fileManager: fileManager, root: root)
        
        // Then
        XCTAssertEqual(try reopened.fetch(forKey: "key"), Data([0xAA]))
        XCTAssertNil(reopened.domain)
    }
    
    @SQLiteActor
    func testInstancesSharingDatabaseSeeEachOthersChanges() throws {
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
    func testValueRoundTrips() throws {
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
    func testAnyKeyIsValid() throws {
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
        let sharedKey = SQLiteKey<Int>(key: "unified", domain: Self.otherStorageDomain)
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
        try await storage.clear(storage: SQLiteStorage.self, forDomain: Self.otherStorageDomain)
        
        // Then
        let deleted = try await storage.fetch(forKey: key)
        let cleared = try await storage.fetch(forKey: sharedKey)
        XCTAssertNil(deleted)
        XCTAssertNil(cleared)
        subscription.cancel()
    }
    
    @SQLiteActor
    func testErrorCaseRootIsAFile() throws {
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
    func testErrorCaseCorruptDatabase() throws {
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
    func testThreadSafety() throws {
        // Given
        let storage = standardStorage!
        let iterations = 5000
        let promise = expectation(description: "testThreadSafety")
        let group = DispatchGroup()
        for _ in 1...iterations { group.enter() }
        
        // When
        DispatchQueue.concurrentPerform(iterations: iterations) { number in
            let operation = Int.random(in: 0...4)
            let key = "\(Int.random(in: 1000...9999))"
            
            Task.detached {
                do {
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
                } catch {
                    XCTFail("Unexpected error \(error)")
                }
                
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            promise.fulfill()
        }
        
        wait(for: [promise], timeout: 5)
    }
    
    // MARK: Helpers
    
    /// A not yet created directory, removed after the test.
    private func makeTemporaryRoot() -> URL {
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { [fileManager] in
            try? fileManager.removeItem(at: root)
        }
        
        return root
    }
    
    /// An empty file, removed after the test.
    private func makeTemporaryFile() throws -> URL {
        let file = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        addTeardownBlock { [fileManager] in
            try? fileManager.removeItem(at: file)
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
