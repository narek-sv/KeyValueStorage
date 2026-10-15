//
//  FileStorageTests.swift
//  
//
//  Created by Narek Sahakyan on 31.12.23.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class FileStorageTests: XCTestCase {
    static let otherStorageDomain = "other"
    var fileManager = FileManager.default
    var standardPath: URL!
    var otherPath: URL!
    var standardStorage: FileStorage!
    var otherStorage: FileStorage!
    
    @FileActor
    override func setUpWithError() throws {
        let id = Bundle.main.bundleIdentifier!
        standardPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(id, isDirectory: true)
        otherPath = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.otherStorageDomain)!.appendingPathComponent(id, isDirectory: true)
        
        try? fileManager.createDirectory(at: standardPath, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: otherPath, withIntermediateDirectories: true)
        try fileManager.clearDirectoryContents(url: standardPath)
        try fileManager.clearDirectoryContents(url: otherPath)
        
        standardStorage = try FileStorage()
        otherStorage = try FileStorage(domain: Self.otherStorageDomain)
    }
    
    @FileActor
    func testFileDomain() {
        XCTAssertEqual(standardStorage.domain, nil)
        XCTAssertEqual(otherStorage.domain, Self.otherStorageDomain)
    }
    
    @FileActor
    func testFileFetch() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        let filePath1 = standardPath.appendingPathComponent(key1).path
        let filePath2 = standardPath.appendingPathComponent(key2).path
        
        // When
        var fetched1 = try standardStorage.fetch(forKey: key1)
        var fetched2 = try standardStorage.fetch(forKey: key2)
        
        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
        
        // When
        XCTAssertTrue(fileManager.createFile(atPath: filePath1, contents: data1))
        fetched1 = try standardStorage.fetch(forKey: key1)
        fetched2 = try standardStorage.fetch(forKey: key2)
        
        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertNil(fetched2)
        
        // When
        try fileManager.removeItem(atPath: filePath1)
        XCTAssertTrue(fileManager.createFile(atPath: filePath1, contents: data2))
        fetched1 = try standardStorage.fetch(forKey: key1)
        fetched2 = try standardStorage.fetch(forKey: key2)
        
        // Then
        XCTAssertEqual(fetched1, data2)
        XCTAssertNil(fetched2)
        
        // When
        try fileManager.removeItem(atPath: filePath1)
        XCTAssertTrue(fileManager.createFile(atPath: filePath1, contents: data1))
        XCTAssertTrue(fileManager.createFile(atPath: filePath2, contents: data2))
        fetched1 = try standardStorage.fetch(forKey: key1)
        fetched2 = try standardStorage.fetch(forKey: key2)
        
        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertEqual(fetched2, data2)
        
        // When
        try fileManager.removeItem(atPath: filePath1)
        try fileManager.removeItem(atPath: filePath2)
        XCTAssertTrue(fileManager.createFile(atPath: filePath2, contents: data1))
        fetched1 = try standardStorage.fetch(forKey: key1)
        fetched2 = try standardStorage.fetch(forKey: key2)
        
        // Then
        XCTAssertNil(fetched1)
        XCTAssertEqual(fetched2, data1)
        
        // When
        try fileManager.removeItem(atPath: filePath2)
        fetched1 = try standardStorage.fetch(forKey: key1)
        fetched2 = try standardStorage.fetch(forKey: key2)
        
        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
    }
    
    @FileActor
    func testFileFetchDifferentDomains() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        let filePath1 = standardPath.appendingPathComponent(key).path
        let filePath2 = otherPath.appendingPathComponent(key).path
        
        // When
        var fetched1 = try standardStorage.fetch(forKey: key)
        var fetched2 = try otherStorage.fetch(forKey: key)
        
        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
        
        // When
        XCTAssertTrue(fileManager.createFile(atPath: filePath1, contents: data1))
        fetched1 = try standardStorage.fetch(forKey: key)
        fetched2 = try otherStorage.fetch(forKey: key)
        
        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertNil(fetched2)
        
        // When
        try fileManager.removeItem(atPath: filePath1)
        XCTAssertTrue(fileManager.createFile(atPath: filePath2, contents: data2))
        fetched1 = try standardStorage.fetch(forKey: key)
        fetched2 = try otherStorage.fetch(forKey: key)
        
        // Then
        XCTAssertNil(fetched1)
        XCTAssertEqual(fetched2, data2)
        
        // When
        
        XCTAssertTrue(fileManager.createFile(atPath: filePath1, contents: data2))
        try fileManager.removeItem(atPath: filePath2)
        fetched1 = try standardStorage.fetch(forKey: key)
        fetched2 = try otherStorage.fetch(forKey: key)
        
        // Then
        XCTAssertEqual(fetched1, data2)
        XCTAssertNil(fetched2)
        
        // When
        try fileManager.removeItem(atPath: filePath1)
        XCTAssertTrue(fileManager.createFile(atPath: filePath1, contents: data1))
        XCTAssertTrue(fileManager.createFile(atPath: filePath2, contents: data2))
        fetched1 = try standardStorage.fetch(forKey: key)
        fetched2 = try otherStorage.fetch(forKey: key)
        
        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertEqual(fetched2, data2)
        
        // When
        try fileManager.removeItem(atPath: filePath1)
        try fileManager.removeItem(atPath: filePath2)
        fetched1 = try standardStorage.fetch(forKey: key)
        fetched2 = try otherStorage.fetch(forKey: key)
        
        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
    }
    
    @FileActor
    func testFileSave() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        let filePath1 = standardPath.appendingPathComponent(key1).path
        let filePath2 = standardPath.appendingPathComponent(key2).path

        // When
        try standardStorage.save(data1, forKey: key1)
        
        // Then
        XCTAssertEqual(fileManager.contents(atPath: filePath1), data1)
        XCTAssertNil(fileManager.contents(atPath: filePath2))
        
        // When
        try standardStorage.save(data2, forKey: key1)
        try standardStorage.save(data2, forKey: key1)
        try standardStorage.save(data2, forKey: key1)
        try standardStorage.save(data2, forKey: key1)
        
        // Then
        XCTAssertEqual(fileManager.contents(atPath: filePath1), data2)
        XCTAssertNil(fileManager.contents(atPath: filePath2))
        
        // When
        try standardStorage.save(data1, forKey: key2)
        
        // Then
        XCTAssertEqual(fileManager.contents(atPath: filePath1), data2)
        XCTAssertEqual(fileManager.contents(atPath: filePath2), data1)
    }
    
    @FileActor
    func testFileSaveDifferentDomains() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        let filePath1 = standardPath.appendingPathComponent(key).path
        let filePath2 = otherPath.appendingPathComponent(key).path
        
        // When
        try standardStorage.save(data1, forKey: key)
        
        // Then
        XCTAssertEqual(fileManager.contents(atPath: filePath1), data1)
        XCTAssertNil(fileManager.contents(atPath: filePath2))
        
        // When
        try otherStorage.save(data2, forKey: key)
        
        // Then
        XCTAssertEqual(fileManager.contents(atPath: filePath1), data1)
        XCTAssertEqual(fileManager.contents(atPath: filePath2), data2)
        
        // When
        try standardStorage.save(data2, forKey: key)
        
        // Then
        XCTAssertEqual(fileManager.contents(atPath: filePath1), data2)
        XCTAssertEqual(fileManager.contents(atPath: filePath2), data2)
    }
    
    @FileActor
    func testFileDelete() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        let filePath1 = standardPath.appendingPathComponent(key1).path
        let filePath2 = standardPath.appendingPathComponent(key2).path
        XCTAssertTrue(fileManager.createFile(atPath: filePath1, contents: data1))
        XCTAssertTrue(fileManager.createFile(atPath: filePath2, contents: data2))
        
        // When
        try standardStorage.delete(forKey: key1)
        
        // Then
        XCTAssertNil(fileManager.contents(atPath: filePath1))
        XCTAssertEqual(fileManager.contents(atPath: filePath2), data2)
        
        // When
        try standardStorage.delete(forKey: key1)
        try standardStorage.delete(forKey: key1)
        try standardStorage.delete(forKey: key1)
        try standardStorage.delete(forKey: key1)

        // Then
        XCTAssertNil(fileManager.contents(atPath: filePath1))
        XCTAssertEqual(fileManager.contents(atPath: filePath2), data2)
        
        // When
        try standardStorage.delete(forKey: key2)
        
        // Then
        XCTAssertNil(fileManager.contents(atPath: filePath1))
        XCTAssertNil(fileManager.contents(atPath: filePath2))
    }
    
    @FileActor
    func testFileDeleteDifferentDomains() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        let filePath1 = standardPath.appendingPathComponent(key).path
        let filePath2 = otherPath.appendingPathComponent(key).path
        XCTAssertTrue(fileManager.createFile(atPath: filePath1, contents: data1))
        XCTAssertTrue(fileManager.createFile(atPath: filePath2, contents: data2))
        
        // When
        try standardStorage.delete(forKey: key)
        
        // Then
        XCTAssertNil(fileManager.contents(atPath: filePath1))
        XCTAssertEqual(fileManager.contents(atPath: filePath2), data2)
        
        // When
        try standardStorage.delete(forKey: key)
        
        // Then
        XCTAssertNil(fileManager.contents(atPath: filePath1))
        XCTAssertEqual(fileManager.contents(atPath: filePath2), data2)
        
        // When
        try otherStorage.delete(forKey: key)
        
        // Then
        XCTAssertNil(fileManager.contents(atPath: filePath1))
        XCTAssertNil(fileManager.contents(atPath: filePath2))
    }
    
    @FileActor
    func testFileSet() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        let filePath1 = standardPath.appendingPathComponent(key1).path
        let filePath2 = standardPath.appendingPathComponent(key2).path
        XCTAssertTrue(fileManager.createFile(atPath: filePath1, contents: data1))
        XCTAssertTrue(fileManager.createFile(atPath: filePath2, contents: data2))

        // When
        try standardStorage.set(data2, forKey: key1)
        
        // Then
        XCTAssertEqual(fileManager.contents(atPath: filePath1), data2)
        XCTAssertEqual(fileManager.contents(atPath: filePath2), data2)
        
        // When
        try standardStorage.set(nil, forKey: key1)
        
        // Then
        XCTAssertNil(fileManager.contents(atPath: filePath1))
        XCTAssertEqual(fileManager.contents(atPath: filePath2), data2)
        
        // When
        try standardStorage.set(data1, forKey: key2)
        
        // Then
        XCTAssertNil(fileManager.contents(atPath: filePath1))
        XCTAssertEqual(fileManager.contents(atPath: filePath2), data1)
        
        // When
        try standardStorage.set(nil, forKey: key2)
        
        // Then
        XCTAssertNil(fileManager.contents(atPath: filePath1))
        XCTAssertNil(fileManager.contents(atPath: filePath2))
    }
    
    @FileActor
    func testFileSetDifferentDomains() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key = "key"
        let filePath1 = standardPath.appendingPathComponent(key).path
        let filePath2 = otherPath.appendingPathComponent(key).path
        XCTAssertTrue(fileManager.createFile(atPath: filePath1, contents: data1))
        XCTAssertTrue(fileManager.createFile(atPath: filePath2, contents: data2))
        
        // When
        try standardStorage.set(data2, forKey: key)
        
        // Then
        XCTAssertEqual(fileManager.contents(atPath: filePath1), data2)
        XCTAssertEqual(fileManager.contents(atPath: filePath2), data2)
        
        // When
        try standardStorage.set(nil, forKey: key)
        
        // Then
        XCTAssertNil(fileManager.contents(atPath: filePath1))
        XCTAssertEqual(fileManager.contents(atPath: filePath2), data2)
        
        // When
        try otherStorage.set(data1, forKey: key)
        
        // Then
        XCTAssertNil(fileManager.contents(atPath: filePath1))
        XCTAssertEqual(fileManager.contents(atPath: filePath2), data1)
        
        // When
        try otherStorage.set(nil, forKey: key)
        
        // Then
        XCTAssertNil(fileManager.contents(atPath: filePath1))
        XCTAssertNil(fileManager.contents(atPath: filePath2))
    }
    
    @FileActor
    func testFileClear() throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        let filePath11 = standardPath.appendingPathComponent(key1).path
        let filePath12 = standardPath.appendingPathComponent(key2).path
        let filePath21 = otherPath.appendingPathComponent(key1).path
        let filePath22 = otherPath.appendingPathComponent(key2).path
        XCTAssertTrue(fileManager.createFile(atPath: filePath11, contents: data1))
        XCTAssertTrue(fileManager.createFile(atPath: filePath12, contents: data2))
        XCTAssertTrue(fileManager.createFile(atPath: filePath21, contents: data1))
        XCTAssertTrue(fileManager.createFile(atPath: filePath22, contents: data2))
        
        // When
        try standardStorage.clear()
        
        // Then
        XCTAssertNil(fileManager.contents(atPath: filePath11))
        XCTAssertNil(fileManager.contents(atPath: filePath12))
        XCTAssertEqual(fileManager.contents(atPath: filePath21), data1)
        XCTAssertEqual(fileManager.contents(atPath: filePath22), data2)
        
        // When
        try standardStorage.clear()
        
        // Then
        XCTAssertNil(fileManager.contents(atPath: filePath11))
        XCTAssertNil(fileManager.contents(atPath: filePath12))
        XCTAssertEqual(fileManager.contents(atPath: filePath21), data1)
        XCTAssertEqual(fileManager.contents(atPath: filePath22), data2)
        
        // When
        XCTAssertTrue(fileManager.createFile(atPath: filePath11, contents: data2))
        XCTAssertTrue(fileManager.createFile(atPath: filePath12, contents: data1))
        try otherStorage.clear()
        
        // Then
        XCTAssertEqual(fileManager.contents(atPath: filePath11), data2)
        XCTAssertEqual(fileManager.contents(atPath: filePath12), data1)
        XCTAssertNil(fileManager.contents(atPath: filePath21))
        XCTAssertNil(fileManager.contents(atPath: filePath22))
        
        // When
        try standardStorage.clear()
        
        // Then
        XCTAssertNil(fileManager.contents(atPath: filePath11))
        XCTAssertNil(fileManager.contents(atPath: filePath12))
        XCTAssertNil(fileManager.contents(atPath: filePath21))
        XCTAssertNil(fileManager.contents(atPath: filePath22))
    }
    
    @FileActor
    func testInvalidKeys() throws {
        // Given
        let data = Data([0xAA, 0xBB, 0xCC])
        let invalidKeys = ["", ".", "..", "../escaped", "a/b", "/absolute", "a\0b", String(repeating: "a", count: 256)]
        try standardStorage.save(data, forKey: "valid")
        
        for key in invalidKeys {
            // When
            XCTAssertThrowsError(try standardStorage.save(data, forKey: key)) { error in
                // Then
                assertInvalidKey(error, key)
            }
            
            // When
            XCTAssertThrowsError(try standardStorage.fetch(forKey: key)) { error in
                // Then
                assertInvalidKey(error, key)
            }
            
            // When
            XCTAssertThrowsError(try standardStorage.delete(forKey: key)) { error in
                // Then
                assertInvalidKey(error, key)
            }
        }
        
        // Then
        XCTAssertEqual(try standardStorage.fetch(forKey: "valid"), data)
        XCTAssertFalse(fileManager.fileExists(atPath: standardPath.deletingLastPathComponent().appendingPathComponent("escaped").path))
    }
    
    @FileActor
    func testValidEdgeCaseKeys() throws {
        // Given
        let data = Data([0xAA, 0xBB, 0xCC])
        let keys = [String(repeating: "a", count: 255), "ключ", ".hidden", "with space", "a:b"]
        
        for key in keys {
            // When
            try standardStorage.save(data, forKey: key)
            
            // Then
            XCTAssertEqual(try standardStorage.fetch(forKey: key), data)
            
            // When
            try standardStorage.delete(forKey: key)
            
            // Then
            XCTAssertNil(try standardStorage.fetch(forKey: key))
        }
    }
    
    @FileActor
    func testErrorCaseDelete() {
        // Given
        let mock = FileManagerMock()
        let storage = FileStorage(fileManager: mock, root: URL(string: "root")!)
        mock.removeItemError = nil

        do {
            // When
            try storage.delete(forKey: "nonExistingFile")
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
        
        // Given
        mock.removeItemError = CocoaError(CocoaError.fileNoSuchFile)

        do {
            // When
            try storage.delete(forKey: "nonExistingFile")
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
        
        // Given
        mock.removeItemError = CocoaError(CocoaError.coderInvalidValue)

        do {
            // When
            try storage.delete(forKey: "nonExistingFile")
        } catch let error as FileStorage.Error {
            // Then
            if case let .other(innerError as CocoaError) = error {
                XCTAssertEqual(innerError.code, CocoaError.coderInvalidValue)
            } else {
                XCTFail("Unexpected error")
            }
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
    }
    
    @FileActor
    func testErrorCaseSave() throws {
        // Given
        let mock = FileManagerMock()
        let storage = FileStorage(fileManager: mock, root: temporaryURL())
        mock.createDirectoryError = CocoaError(CocoaError.coderInvalidValue)
        
        do {
            // When
            try storage.save(.init(), forKey: "nonExistingFile")
            XCTFail("Expected error")
        } catch let error as FileStorage.Error {
            // Then
            if case let .other(innerError as CocoaError) = error {
                XCTAssertEqual(innerError.code, CocoaError.coderInvalidValue)
            } else {
                XCTFail("Unexpected error")
            }
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
        
        // Given
        let file = temporaryURL()
        try Data().write(to: file)
        let blockedStorage = FileStorage(fileManager: fileManager, root: file)
        
        do {
            // When
            try blockedStorage.save(.init(), forKey: "key")
            XCTFail("Expected error")
        } catch let error as FileStorage.Error {
            // Then
            if case .other = error {
                // ok
            } else {
                XCTFail("Unexpected error")
            }
        } catch {
            // Then
            XCTFail("Unexpected error")
        }
        
        try fileManager.removeItem(at: file)
    }
    
    @FileActor
    func testSaveCreatesMissingDirectory() throws {
        // Given
        let root = temporaryURL()
        let storage = FileStorage(fileManager: fileManager, root: root)
        let data = Data([0xAA, 0xBB, 0xCC])
        
        // When
        try storage.save(data, forKey: "key")
        
        // Then
        XCTAssertEqual(try storage.fetch(forKey: "key"), data)
        
        // When
        try fileManager.removeItem(at: root)
        try storage.save(data, forKey: "key")
        
        // Then
        XCTAssertEqual(try storage.fetch(forKey: "key"), data)
        
        try fileManager.removeItem(at: root)
    }
    
    @FileActor
    func testErrorCaseFetch() throws {
        // Given
        let root = temporaryURL()
        let storage = FileStorage(fileManager: fileManager, root: root)
        
        // When
        let missing = try storage.fetch(forKey: "key")
        
        // Then
        XCTAssertNil(missing)
        
        // Given
        try fileManager.createDirectory(at: root.appendingPathComponent("key"), withIntermediateDirectories: true)
        
        // When
        XCTAssertThrowsError(try storage.fetch(forKey: "key")) { error in
            // Then
            guard case .other = error as? FileStorage.Error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
        
        try fileManager.removeItem(at: root)
    }
    
    @FileActor
    func testThreadSafety() throws {
        // Given
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
                        _ = try await self.standardStorage.fetch(forKey: key)
                    case 1:
                        try await self.standardStorage.save(.init(), forKey: key)
                    case 2:
                        try await self.standardStorage.delete(forKey: key)
                    case 3:
                        try await self.standardStorage.set(Bool.random() ? nil : .init(), forKey: key)
                    case 4:
                        try await self.standardStorage.clear()
                    default:
                        break
                    }
                } catch {
                    XCTFail("Unexpected error")
                }
                
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            promise.fulfill()
        }
        
        wait(for: [promise], timeout: 5)
    }
    
    private func temporaryURL() -> URL {
        fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
    
    private func assertInvalidKey(_ error: Error, _ key: String, line: UInt = #line) {
        guard case let .invalidKey(invalidKey) = error as? FileStorage.Error else {
            return XCTFail("Unexpected error \(error)", line: line)
        }
        
        XCTAssertEqual(invalidKey, key, line: line)
    }
}

extension FileManager {
    func clearDirectoryContents(url: URL) throws {
        if let paths = try? contentsOfDirectory(atPath: url.path) {
            for path in paths {
                try removeItem(at: url.appendingPathComponent(path))
            }
        }
    }
}
