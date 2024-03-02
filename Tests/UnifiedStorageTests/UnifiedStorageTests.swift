//
//  UnifiedStorageTests.swift
//
//
//  Created by Narek Sahakyan on 12.12.23.
//

import XCTest
import Foundation
@testable import UnifiedStorage

final class UnifiedStorageTests: XCTestCase {
    func testStorage() async throws {
        // Given
        let key1 = InMemoryKey<String>(key: "key1")
        let key2 = InMemoryKey<String>(key: "key2")
        let key3 = InMemoryKey<String>(key: "key3", domain: "other")
        let key4 = InMemoryKey<String>(key: "key4", domain: "other")
        let storage = UnifiedStorage(factory: MockedUnifiedStorageFactory())
        
        // When
        var fetched1 = try await storage.fetch(forKey: key1)
        var fetched2 = try await storage.fetch(forKey: key2)
        var fetched3 = try await storage.fetch(forKey: key3)
        var fetched4 = try await storage.fetch(forKey: key4)

        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
        XCTAssertNil(fetched3)
        XCTAssertNil(fetched4)
        
        // When
        try await storage.save("newData1", forKey: key1)
        try await storage.save("newData2", forKey: key2)
        try await storage.save("newData3", forKey: key3)
        try await storage.save("newData4", forKey: key4)
        
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)
        fetched3 = try await storage.fetch(forKey: key3)
        fetched4 = try await storage.fetch(forKey: key4)
        
        // Then
        XCTAssertEqual(fetched1, "newData1")
        XCTAssertEqual(fetched2, "newData2")
        XCTAssertEqual(fetched3, "newData3")
        XCTAssertEqual(fetched4, "newData4")
        
        // When
        try await storage.delete(forKey: key1)
        try await storage.delete(forKey: key2)
        try await storage.delete(forKey: key3)
        try await storage.delete(forKey: key4)
        
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)
        fetched3 = try await storage.fetch(forKey: key3)
        fetched4 = try await storage.fetch(forKey: key4)
        
        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
        XCTAssertNil(fetched3)
        XCTAssertNil(fetched4)
        
        // When
        try await storage.set("newNewData1", forKey: key1)
        try await storage.set("newNewData2", forKey: key2)
        try await storage.set("newNewData3", forKey: key3)
        try await storage.set("newNewData4", forKey: key4)
        
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)
        fetched3 = try await storage.fetch(forKey: key3)
        fetched4 = try await storage.fetch(forKey: key4)
        
        // Then
        XCTAssertEqual(fetched1, "newNewData1")
        XCTAssertEqual(fetched2, "newNewData2")
        XCTAssertEqual(fetched3, "newNewData3")
        XCTAssertEqual(fetched4, "newNewData4")
        
        // When
        try await storage.set(nil, forKey: key1)
        try await storage.set(nil, forKey: key2)
        try await storage.set(nil, forKey: key3)
        try await storage.set(nil, forKey: key4)
        
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)
        fetched3 = try await storage.fetch(forKey: key3)
        fetched4 = try await storage.fetch(forKey: key4)
        
        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
        XCTAssertNil(fetched3)
        XCTAssertNil(fetched4)
        
        // When
        try await storage.save("newData1", forKey: key1)
        try await storage.save("newData2", forKey: key2)
        try await storage.save("newData3", forKey: key3)
        try await storage.save("newData4", forKey: key4)
        
        try await storage.clear(storage: KeychainStorage.self)
        
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)
        fetched3 = try await storage.fetch(forKey: key3)
        fetched4 = try await storage.fetch(forKey: key4)
        
        // Then
        XCTAssertEqual(fetched1, "newData1")
        XCTAssertEqual(fetched2, "newData2")
        XCTAssertEqual(fetched3, "newData3")
        XCTAssertEqual(fetched4, "newData4")
        
        // When
        try await storage.clear(storage: InMemoryStorage.self, forDomain: nil)
        
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)
        fetched3 = try await storage.fetch(forKey: key3)
        fetched4 = try await storage.fetch(forKey: key4)
        
        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
        XCTAssertEqual(fetched3, "newData3")
        XCTAssertEqual(fetched4, "newData4")
        
        // When
        try await storage.clear(storage: InMemoryStorage.self)
        
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)
        fetched3 = try await storage.fetch(forKey: key3)
        fetched4 = try await storage.fetch(forKey: key4)
        
        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
        XCTAssertNil(fetched3)
        XCTAssertNil(fetched4)
    }
}

final class MockedUnifiedStorageFactory: DefaultUnifiedStorageFactory {
    override func dataStorage<Storage: KeyValueDataStorage>(for domain: Storage.Domain?) async throws -> Storage {
        switch Storage.self {
        case is InMemoryMock.Type:
            if let domain = domain as? InMemoryStorage.Domain {
                return await InMemoryMock(domain: domain) as! Storage
            } else {
                return await InMemoryMock() as! Storage
            }
        default:
            return try await super.dataStorage(for: domain)
        }
    }
}
