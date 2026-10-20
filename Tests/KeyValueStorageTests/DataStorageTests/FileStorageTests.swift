//
//  FileStorageTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.12.23.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class FileStorageTests: XCTestCase {
    static let otherStorageScope = "other"
    var fileManager = FileManager.default
    var standardPath: URL!
    var otherPath: URL!
    var standardStorage: FileStorage!
    var otherStorage: FileStorage!
    
    @FileActor
    override func setUp() async throws {
        let id = Bundle.main.bundleIdentifier!
        standardPath = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("KeyValueStorage/Files", isDirectory: true)
        otherPath = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.otherStorageScope)!
            .appendingPathComponent("KeyValueStorage/Files", isDirectory: true)
        
        try? fileManager.createDirectory(at: standardPath, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: otherPath, withIntermediateDirectories: true)
        try fileManager.clearDirectoryContents(url: standardPath)
        try fileManager.clearDirectoryContents(url: otherPath)
        
        standardStorage = try FileStorage()
        otherStorage = try FileStorage(scope: Self.otherStorageScope)
    }
    
    @FileActor
    func testFileScope() async {
        XCTAssertEqual(standardStorage.scope, nil)
        XCTAssertEqual(otherStorage.scope, Self.otherStorageScope)
    }
    
    @FileActor
    func testFileFetch() async throws {
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
    func testFileFetchDifferentScopes() async throws {
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
    func testFileSave() async throws {
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
    func testFileSaveDifferentScopes() async throws {
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
    func testFileDelete() async throws {
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
    func testFileDeleteDifferentScopes() async throws {
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
    func testFileSet() async throws {
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
    func testFileSetDifferentScopes() async throws {
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
    func testFileClear() async throws {
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
    func testInvalidKeys() async throws {
        // Given
        let data = Data([0xAA, 0xBB, 0xCC])
        let invalidKeys = ["", ".", "..", "../escaped", "a/b", "/absolute", "a\0b", String(repeating: "a", count: 256), String(repeating: "ж", count: 128), String(repeating: "A", count: 86)]
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
    func testValidEdgeCaseKeys() async throws {
        // Given
        let data = Data([0xAA, 0xBB, 0xCC])
        let keys = [String(repeating: "a", count: 255), String(repeating: "ж", count: 127), String(repeating: "A", count: 85), "ключ", "🔑", ".hidden", "key.", " padded ", "with space", "a:b"]
        
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
    func testErrorCaseDelete() async {
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
    func testErrorCaseSave() async throws {
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
    func testSaveCreatesMissingDirectory() async throws {
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
    func testErrorCaseFetch() async throws {
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
    func testErrorCaseClear() async throws {
        try XCTSkipIf(getuid() == 0, "File permissions are not enforced for root")
        
        // Given
        let root = makeTemporaryRoot()
        let storage = FileStorage(fileManager: fileManager, root: root)
        
        // When
        XCTAssertNoThrow(try storage.clear())
        
        // Then
        XCTAssertFalse(fileManager.fileExists(atPath: root.path))
        
        // Given
        try storage.save(Data([0xAA]), forKey: "key")
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        
        // When
        XCTAssertThrowsError(try storage.clear()) { error in
            // Then
            guard case let .other(innerError as CocoaError) = error as? FileStorage.Error else {
                return XCTFail("Unexpected error \(error)")
            }
            
            XCTAssertEqual(innerError.code, CocoaError.fileReadNoPermission)
        }
        
        // Given
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        let file = try makeTemporaryFile()
        let blockedStorage = FileStorage(fileManager: fileManager, root: file)
        
        // When
        XCTAssertThrowsError(try blockedStorage.clear()) { error in
            // Then
            guard case .other = error as? FileStorage.Error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
        
        // Then
        XCTAssertEqual(try storage.fetch(forKey: "key"), Data([0xAA]))
    }
    
    @FileActor
    func testDefaultLocation() async throws {
        // Given
        let id = Bundle.main.bundleIdentifier!
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(id).path
        let expectedPath = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(id)
            .appendingPathComponent("KeyValueStorage")
            .appendingPathComponent(FileStorage.directoryName)
            .appendingPathComponent("key")
            .path
        
        // When
        try standardStorage.save(Data([0xAA]), forKey: "key")
        
        // Then
        XCTAssertEqual(FileStorage.directoryName, "Files")
        XCTAssertEqual(fileManager.contents(atPath: expectedPath), Data([0xAA]))
        XCTAssertFalse(fileManager.fileExists(atPath: documentsPath))
    }
    
    @FileActor
    func testSharedLocationDoesNotDependOnBundleIdentifier() async throws {
        // Given
        let expectedPath = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.otherStorageScope)!
            .appendingPathComponent("KeyValueStorage")
            .appendingPathComponent(FileStorage.directoryName)
            .appendingPathComponent("key")
            .path
        
        // When
        try otherStorage.save(Data([0xAA]), forKey: "key")
        let sameScopeStorage = try FileStorage(scope: Self.otherStorageScope)
        
        // Then
        XCTAssertEqual(fileManager.contents(atPath: expectedPath), Data([0xAA]))
        XCTAssertFalse(expectedPath.contains(Bundle.main.bundleIdentifier!))
        XCTAssertEqual(try sameScopeStorage.fetch(forKey: "key"), Data([0xAA]))
    }
    
    @FileActor
    func testCustomRoot() async throws {
        // Given
        let root = makeTemporaryRoot()
        let storage = FileStorage(fileManager: fileManager, root: root)
        
        // When
        try storage.save(Data([0xAA]), forKey: "key")
        
        // Then
        XCTAssertNil(storage.scope)
        XCTAssertEqual(fileManager.contents(atPath: root.appendingPathComponent("key").path), Data([0xAA]))
    }
    
    @FileActor
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
        XCTAssertEqual(try standardStorage.fetch(forKey: "empty"), Data())
        XCTAssertNotNil(try standardStorage.fetch(forKey: "empty"))
    }
    
    @FileActor
    func testOverwriteNeverExposesMissingOrPartialValue() async throws {
        // Given
        let root = makeTemporaryRoot()
        let storage = FileStorage(fileManager: fileManager, root: root)
        let values = [Data(repeating: 0x01, count: 64 * 1024), Data(repeating: 0x02, count: 256 * 1024)]
        try storage.save(values[0], forKey: "key")
        let reader = ConcurrentReader(url: root.appendingPathComponent("key"), expectedValues: values)
        
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
    
    @FileActor
    func testSaveLeavesOnlyValueFiles() async throws {
        // Given
        let root = makeTemporaryRoot()
        let storage = FileStorage(fileManager: fileManager, root: root)
        
        // When
        for index in 0..<100 {
            try storage.save(Data([UInt8(index)]), forKey: "key\(index % 10)")
        }
        
        // Then
        XCTAssertEqual(Set(try fileManager.contentsOfDirectory(atPath: root.path)), Set((0..<10).map { "key\($0)" }))
    }
    
    @FileActor
    func testInstancesSharingRootSeeEachOthersChanges() async throws {
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let root = makeTemporaryRoot()
        let first = FileStorage(fileManager: fileManager, root: root)
        let second = FileStorage(fileManager: fileManager, root: root)
        
        // When
        try first.save(data1, forKey: "key")
        
        // Then
        XCTAssertEqual(try second.fetch(forKey: "key"), data1)
        
        // When
        try second.save(data2, forKey: "key")
        
        // Then
        XCTAssertEqual(try first.fetch(forKey: "key"), data2)
        
        // When
        try second.delete(forKey: "key")
        
        // Then
        XCTAssertNil(try first.fetch(forKey: "key"))
        
        // When
        try first.save(data1, forKey: "other")
        try second.clear()
        
        // Then
        XCTAssertNil(try first.fetch(forKey: "other"))
    }
    
    @FileActor
    func testOperationsWithoutSavedValuesDontCreateDirectory() async throws {
        // Given
        let root = makeTemporaryRoot()
        let storage = FileStorage(fileManager: fileManager, root: root)
        
        // When
        let fetched = try storage.fetch(forKey: "key")
        try storage.delete(forKey: "key")
        try storage.set(nil, forKey: "key")
        try storage.clear()
        XCTAssertThrowsError(try storage.save(Data([0xAA]), forKey: ""))
        
        // Then
        XCTAssertNil(fetched)
        XCTAssertFalse(fileManager.fileExists(atPath: root.path))
    }
    
    @FileActor
    func testClearRemovesEverythingInsideRoot() async throws {
        // Given
        let data = Data([0xAA, 0xBB, 0xCC])
        let root = makeTemporaryRoot()
        let storage = FileStorage(fileManager: fileManager, root: root)
        try storage.save(data, forKey: "key")
        try storage.save(data, forKey: ".hidden")
        try fileManager.createDirectory(at: root.appendingPathComponent("folder/nested"), withIntermediateDirectories: true)
        try data.write(to: root.appendingPathComponent("folder/nested/file"))
        
        // When
        try storage.clear()
        
        // Then
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: root.path), [])
        
        // When
        try storage.save(data, forKey: "key")
        
        // Then
        XCTAssertEqual(try storage.fetch(forKey: "key"), data)
    }
    
    @FileActor
    func testKeysThatDifferOnlyInCaseAreSeparate() async throws {
        // Given
        let root = makeTemporaryRoot()
        let storage = FileStorage(fileManager: fileManager, root: root)
        let keys = ["key", "Key", "KEY", "σ", "ς", "Σ"]
        
        // When
        for (index, key) in keys.enumerated() {
            try storage.save(Data([UInt8(index)]), forKey: key)
        }
        
        // Then
        for (index, key) in keys.enumerated() {
            XCTAssertEqual(try storage.fetch(forKey: key), Data([UInt8(index)]), "key \(key)")
        }
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: root.path).count, keys.count)
        
        // When
        try storage.delete(forKey: "key")
        
        // Then
        XCTAssertNil(try storage.fetch(forKey: "key"))
        XCTAssertEqual(try storage.fetch(forKey: "Key"), Data([1]))
    }
    
    @FileActor
    func testFileNamesEncodeCharactersThatChangeWithCase() async throws {
        // Given
        let root = makeTemporaryRoot()
        let storage = FileStorage(fileManager: fileManager, root: root)
        let fileNames = [
            "key": "key",
            "Key": "%4Bey",
            "userID": "user%49%44",
            "100%": "100%25",
            "ключ": "ключ",
            "Ключ": "%D0%9Aлюч",
            "straße": "stra%C3%9Fe",
            "🔑 1_a.b": "🔑 1_a.b"
        ]
        
        // When
        for key in fileNames.keys {
            try storage.save(Data([0xAA]), forKey: key)
        }
        
        // Then
        XCTAssertEqual(Set(try fileManager.contentsOfDirectory(atPath: root.path)), Set(fileNames.values))
    }
    
    @FileActor
    func testCanonicallyEquivalentKeysShareAFile() async throws {
        // Given
        let root = makeTemporaryRoot()
        let storage = FileStorage(fileManager: fileManager, root: root)
        
        // When
        try storage.save(Data([0xAA]), forKey: "Cafe\u{301} E\u{301}")
        
        // Then
        XCTAssertEqual(try storage.fetch(forKey: "Caf\u{E9} \u{C9}"), Data([0xAA]))
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: root.path), ["%43af\u{E9} %C3%89"])
    }
    
    @FileActor
    func testErrorCaseRootIsAFile() async throws {
        // Given
        let file = try makeTemporaryFile()
        let storage = FileStorage(fileManager: fileManager, root: file)
        
        // When
        XCTAssertThrowsError(try storage.fetch(forKey: "key")) { error in
            // Then
            assertOtherError(error)
        }
        
        // When
        XCTAssertThrowsError(try storage.delete(forKey: "key")) { error in
            // Then
            assertOtherError(error)
        }
    }
    
    @FileActor
    func testErrorCaseReadOnlyDirectory() async throws {
        try XCTSkipIf(getuid() == 0, "File permissions are not enforced for root")
        
        // Given
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let root = makeTemporaryRoot()
        let storage = FileStorage(fileManager: fileManager, root: root)
        try storage.save(data1, forKey: "key")
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        let operations: [() throws -> Void] = [
            { try storage.save(data2, forKey: "new") },
            { try storage.save(data2, forKey: "key") },
            { try storage.delete(forKey: "key") },
            { try storage.clear() }
        ]
        
        for operation in operations {
            // When
            XCTAssertThrowsError(try operation()) { error in
                // Then
                assertOtherError(error, CocoaError.fileWriteNoPermission)
            }
        }
        
        // Then
        XCTAssertEqual(try storage.fetch(forKey: "key"), data1)
        XCTAssertNil(try storage.fetch(forKey: "new"))
    }
    
    @FileActor
    func testErrorCaseUnreadableFile() async throws {
        try XCTSkipIf(getuid() == 0, "File permissions are not enforced for root")
        
        // Given
        let root = makeTemporaryRoot()
        let storage = FileStorage(fileManager: fileManager, root: root)
        try storage.save(Data([0xAA, 0xBB, 0xCC]), forKey: "key")
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.appendingPathComponent("key").path)
        
        // When
        XCTAssertThrowsError(try storage.fetch(forKey: "key")) { error in
            // Then
            assertOtherError(error, CocoaError.fileReadNoPermission)
        }
        
        // When
        try storage.delete(forKey: "key")
        
        // Then
        XCTAssertNil(try storage.fetch(forKey: "key"))
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
    
    private func assertOtherError(_ error: Error, _ code: CocoaError.Code? = nil, line: UInt = #line) {
        guard case let .other(innerError) = error as? FileStorage.Error else {
            return XCTFail("Unexpected error \(error)", line: line)
        }
        
        if let code {
            XCTAssertEqual((innerError as? CocoaError)?.code, code, line: line)
        }
    }
    
    /// A not yet created directory, removed after the test even if its permissions were changed.
    private func makeTemporaryRoot() -> URL {
        let root = temporaryURL()
        // FileManager isn't Sendable, so the block can't capture it
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        
        return root
    }
    
    /// An empty file, removed after the test.
    private func makeTemporaryFile() throws -> URL {
        let file = temporaryURL()
        try Data().write(to: file)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: file)
        }
        
        return file
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

/// Reads a file in a tight loop on its own thread, outside the storage's actor, like another process would.
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

extension FileManager {
    func clearDirectoryContents(url: URL) throws {
        if let paths = try? contentsOfDirectory(atPath: url.path) {
            for path in paths {
                try removeItem(at: url.appendingPathComponent(path))
            }
        }
    }
}
