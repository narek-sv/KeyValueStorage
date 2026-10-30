//
//  DataCodersTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 02.03.24.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class DataCodersTests: XCTestCase {
    func testJSONCoding() throws {
        // Given
        let coder = JSONDataCoder()
        let codable1 = "rootObject"
        let codable2 = ["rootObject"]

        // When
        let encoded1 = try coder.encode(codable1)
        let encoded2 = try coder.encode(codable2)

        // Then
        XCTAssertFalse(encoded1.isEmpty)
        XCTAssertFalse(encoded2.isEmpty)
        
        // When
        let decoded1 = try coder.decode(encoded1) as String
        let decoded2 = try coder.decode(encoded2) as [String]

        // Then
        XCTAssertEqual(decoded1, codable1)
        XCTAssertEqual(decoded2, codable2)

        
    }
    
    func testPropertyListCoding() throws {
        // Given
        let coder = PropertyListDataCoder()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        
        // When
        let decodedString = try coder.decode(coder.encode("rootObject")) as String
        let decodedInt = try coder.decode(coder.encode(42)) as Int
        let decodedBool = try coder.decode(coder.encode(true)) as Bool
        let decodedDate = try coder.decode(coder.encode(date)) as Date
        let decodedData = try coder.decode(coder.encode(Data([0xAA]))) as Data
        let decodedArray = try coder.decode(coder.encode(["rootObject"])) as [String]
        let decodedDictionary = try coder.decode(coder.encode(["key": 1])) as [String: Int]
        
        // Then
        XCTAssertEqual(decodedString, "rootObject")
        XCTAssertEqual(decodedInt, 42)
        XCTAssertEqual(decodedBool, true)
        XCTAssertEqual(decodedDate, date)
        XCTAssertEqual(decodedData, Data([0xAA]))
        XCTAssertEqual(decodedArray, ["rootObject"])
        XCTAssertEqual(decodedDictionary, ["key": 1])
    }
    
    func testPropertyListFormat() throws {
        // Given
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let binaryCoder = PropertyListDataCoder()
        let xmlCoder = PropertyListDataCoder(encoder: encoder)
        
        // When
        let binary = try binaryCoder.encode("rootObject")
        let xml = try xmlCoder.encode("rootObject")
        let decoded = try binaryCoder.decode(xml) as String
        
        // Then
        XCTAssertTrue(binary.starts(with: Data("bplist00".utf8)))
        XCTAssertTrue(String(decoding: xml, as: UTF8.self).contains("<string>rootObject</string>"))
        XCTAssertEqual(decoded, "rootObject")
    }
    
    func testPropertyListDecodingRequiresExactlyOneValue() throws {
        // Given
        let coder = PropertyListDataCoder()
        let encoder = PropertyListEncoder()
        
        for values in [[String](), ["a", "b"]] {
            do {
                // When
                _ = try coder.decode(encoder.encode(values)) as String
                XCTFail("Expected error")
            } catch DecodingError.dataCorrupted {
                // Then
            } catch {
                XCTFail("Unexpected error \(error)")
            }
        }
    }
    
    func testPropertyListCodingStorage() async throws {
        // Given
        let storage = KeyValueCodingStorage(storage: InMemoryStorage(scope: .own(namespace: "propertyList")), coder: PropertyListDataCoder())
        let key = KeyValueCodingStorageKey<InMemoryStorage, String>(key: "key")
        
        // When
        try await storage.save("Alice", forKey: key)
        
        // Then
        let fetched = try await storage.fetch(forKey: key)
        XCTAssertEqual(fetched, "Alice")
    }
}
