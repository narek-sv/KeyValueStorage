//
//  DataCodersTests.swift
//
//
//  Created by Narek Sahakyan on 02.03.24.
//

import XCTest
import Foundation
@testable import UnifiedStorage

final class DataCodersTests: XCTestCase {
    func testJSONCoding() async throws {
        // Given
        let coder = JSONDataCoder()
        let codable1 = "rootObject"
        let codable2 = ["rootObject"]

        // When
        let encoded1 = try await coder.encode(codable1)
        let encoded2 = try await coder.encode(codable2)

        // Then
        XCTAssertFalse(encoded1.isEmpty)
        XCTAssertFalse(encoded2.isEmpty)
        
        // When
        let decoded1 = try await coder.decode(encoded1) as String
        let decoded2 = try await coder.decode(encoded2) as [String]

        // Then
        XCTAssertEqual(decoded1, codable1)
        XCTAssertEqual(decoded2, codable2)

        
    }
    
    func testXMLCoding() async throws {
        // Given
        let coder = XMLDataCoder()
        let codable = ["rootObject"]
        
        // When
        let encoded = try await coder.encode(codable)
        
        // Then
        XCTAssertFalse(encoded.isEmpty)
        
        // When
        let decoded = try await coder.decode(encoded) as [String]
        
        // Then
        XCTAssertEqual(decoded, codable)
        
        // When - Then
        do {
            _ = try await coder.encode("rootObject")
            XCTFail("XML parser cant decode root objects")
        } catch { }
    }
}
