//
//  RawDataCoderTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 15.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class RawDataCoderTests: XCTestCase {
    func testDataIsStoredAsIs() throws {
        // Given
        let coder = RawDataCoder()
        
        for value in [Data([0x00, 0xFF, 0x10]), Data()] {
            // When
            let encoded = try coder.encode(value)
            let decoded = try coder.decode(encoded) as Data
            
            // Then
            XCTAssertEqual(encoded, value)
            XCTAssertEqual(decoded, value)
        }
    }
    
    func testStringIsStoredAsUTF8() throws {
        // Given
        let coder = RawDataCoder()
        
        for value in ["token", "ключ 🔑", ""] {
            // When
            let encoded = try coder.encode(value)
            let decoded = try coder.decode(encoded) as String
            
            // Then
            XCTAssertEqual(encoded, Data(value.utf8))
            XCTAssertEqual(decoded, value)
        }
    }
    
    func testDecodingInvalidUTF8Throws() throws {
        // Given
        let coder = RawDataCoder()
        
        do {
            // When
            _ = try coder.decode(Data([0xFF, 0xFE])) as String
            XCTFail("Expected error")
        } catch DecodingError.dataCorrupted {
            // Then
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }
    
    func testOtherTypesUseFallback() throws {
        // JSONEncoder doesn't keep the order of keys stable, so the bytes are only comparable when the keys are sorted
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        
        for fallback in [JSONDataCoder(encoder: encoder) as DataCoder, PropertyListDataCoder()] {
            // Given
            let coder = RawDataCoder(fallback: fallback)
            
            // When - Then
            try assertUsesFallback(42, coder, fallback)
            try assertUsesFallback(true, coder, fallback)
            try assertUsesFallback(3.5, coder, fallback)
            try assertUsesFallback(Date(timeIntervalSince1970: 3), coder, fallback)
            try assertUsesFallback(["a", "b"], coder, fallback)
            try assertUsesFallback(Optional("token"), coder, fallback)
            try assertUsesFallback(Optional(Data([0xAA])), coder, fallback)
            try assertUsesFallback(Custom(id: 1, name: "name"), coder, fallback)
        }
    }
    
    func testCodingStorageUsesRawCoderByDefault() throws {
        // Given
        let underlyingStorage = InMemoryStorage(scope: .own(namespace: "rawDefault"))
        let storage = KeyValueCodingStorage(storage: underlyingStorage)
        
        // When
        try storage.save(Data([0xAA, 0xBB]), forKey: KeyValueCodingStorageKey<InMemoryStorage, Data>(key: "data"))
        try storage.save("token", forKey: KeyValueCodingStorageKey<InMemoryStorage, String>(key: "string"))
        try storage.save(42, forKey: KeyValueCodingStorageKey<InMemoryStorage, Int>(key: "int"))
        
        // Then
        let data = underlyingStorage.fetch(forKey: "data")
        let string = underlyingStorage.fetch(forKey: "string")
        let int = underlyingStorage.fetch(forKey: "int")
        XCTAssertEqual(data, Data([0xAA, 0xBB]))
        XCTAssertEqual(string, Data("token".utf8))
        XCTAssertEqual(int, try JSONEncoder().encode(42))
        
        underlyingStorage.clear()
    }
    
    func testReadsRawValuesSavedWithoutACoder() async throws {
        // Given: raw bytes saved through the data storage, as code without a coder would
        let scope = UserDefaultsStorage.Scope.own(namespace: "rawInterop-\(UUID().uuidString)")
        let userDefaults = try UserDefaultsStorage(scope: scope)
        defer { userDefaults.clear() }
        try userDefaults.save(Data([0x01, 0x02, 0x03]), forKey: "token")
        try userDefaults.save(Data("Alice".utf8), forKey: "name")
        let storage = UnifiedStorage()
        
        // When
        let token = try await storage.fetch(forKey: UserDefaultsKey<Data>(key: "token", scope: scope))
        let name = try await storage.fetch(forKey: UserDefaultsKey<String>(key: "name", scope: scope))
        
        // Then
        XCTAssertEqual(token, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(name, "Alice")
    }
    
    // MARK: Helpers
    
    private func assertUsesFallback<Value: CodingValue & Equatable>(_ value: Value, _ coder: RawDataCoder, _ fallback: any DataCoder, line: UInt = #line) throws {
        let encoded = try coder.encode(value)
        let expected = try fallback.encode(value)
        let decoded = try coder.decode(encoded) as Value
        
        XCTAssertEqual(encoded, expected, line: line)
        XCTAssertEqual(decoded, value, line: line)
    }
    
    private struct Custom: Codable, Equatable {
        let id: Int
        let name: String
    }
}
