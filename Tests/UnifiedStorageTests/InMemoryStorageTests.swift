//
//  InMemoryStorageTests.swift
//  
//
//  Created by Narek Sahakyan on 31.12.23.
//

import XCTest
import Foundation
@testable import UnifiedStorage

final class InMemoryStorageTests: XCTestCase {
    static let Storage = InMemoryStorage.self
    
    @InMemoryActor
    func testInMemoryFetch() async throws {
        // Given
        let storage = try InMemoryStorage()
        let data1 = Data([0xAA, 0xBB, 0xCC])
        let data2 = Data([0xDD, 0xEE, 0xFF])
        let key1 = "key1"
        let key2 = "key2"
        InMemoryStorage.container = [:]
        
        // When
        var fetched1 = try await storage.fetch(forKey: key1)
        var fetched2 = try await storage.fetch(forKey: key2)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)

        // When
        InMemoryStorage.container = [nil: [key1: data1]]
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertNil(fetched2)

        // When
        InMemoryStorage.container = [nil: [key1: data2]]
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)

        // Then
        XCTAssertEqual(fetched1, data2)
        XCTAssertNil(fetched2)
        
        // When
        InMemoryStorage.container = [nil: [key1: data1, key2: data2]]
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)

        // Then
        XCTAssertEqual(fetched1, data1)
        XCTAssertEqual(fetched2, data2)
        
        // When
        InMemoryStorage.container = [nil: [key2: data1]]
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertEqual(fetched2, data1)
        
        // When
        InMemoryStorage.container = [nil: [:]]
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
    }
}
