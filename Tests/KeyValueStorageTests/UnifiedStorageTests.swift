//
//  UnifiedStorageTests.swift
//
//
//  Created by Narek Sahakyan on 12.12.23.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class UnifiedStorageTests: XCTestCase {
    
    override func setUp() async throws {
        await InMemoryStorage().clear()
        await InMemoryStorage(domain: "other").clear()
        
        await UserDefaultsStorage().clear()
        try await UserDefaultsStorage(domain: "other").clear()
    }
    
    func testStorage() async throws {
        // Given
        let key1 = InMemoryKey<String>(key: "key1")
        let key2 = InMemoryKey<String>(key: "key2")
        let key3 = InMemoryKey<String>(key: "key3", domain: "other")
        let key4 = InMemoryKey<String>(key: "key4", domain: "other")
        let key5 = UserDefaultsKey<String>(key: "key1")
        let key6 = UserDefaultsKey<String>(key: "key2")
        let key7 = UserDefaultsKey<String>(key: "key3", domain: "other")
        let key8 = UserDefaultsKey<String>(key: "key4", domain: "other")
        let storage = UnifiedStorage()
        
        // When
        var fetched1 = try await storage.fetch(forKey: key1)
        var fetched2 = try await storage.fetch(forKey: key2)
        var fetched3 = try await storage.fetch(forKey: key3)
        var fetched4 = try await storage.fetch(forKey: key4)
        var fetched5 = try await storage.fetch(forKey: key5)
        var fetched6 = try await storage.fetch(forKey: key6)
        var fetched7 = try await storage.fetch(forKey: key7)
        var fetched8 = try await storage.fetch(forKey: key8)
        
        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
        XCTAssertNil(fetched3)
        XCTAssertNil(fetched4)
        XCTAssertNil(fetched5)
        XCTAssertNil(fetched6)
        XCTAssertNil(fetched7)
        XCTAssertNil(fetched8)
        
        // When
        try await storage.save("data1", forKey: key1)
        try await storage.save("data2", forKey: key2)
        try await storage.save("data3", forKey: key3)
        try await storage.save("data4", forKey: key4)
        try await storage.save("data5", forKey: key5)
        try await storage.save("data6", forKey: key6)
        try await storage.save("data7", forKey: key7)
        try await storage.save("data8", forKey: key8)
        
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)
        fetched3 = try await storage.fetch(forKey: key3)
        fetched4 = try await storage.fetch(forKey: key4)
        fetched5 = try await storage.fetch(forKey: key5)
        fetched6 = try await storage.fetch(forKey: key6)
        fetched7 = try await storage.fetch(forKey: key7)
        fetched8 = try await storage.fetch(forKey: key8)
        
        // Then
        XCTAssertEqual(fetched1, "data1")
        XCTAssertEqual(fetched2, "data2")
        XCTAssertEqual(fetched3, "data3")
        XCTAssertEqual(fetched4, "data4")
        XCTAssertEqual(fetched5, "data5")
        XCTAssertEqual(fetched6, "data6")
        XCTAssertEqual(fetched7, "data7")
        XCTAssertEqual(fetched8, "data8")
                
        // When
        try await storage.delete(forKey: key1)
        try await storage.delete(forKey: key2)
        try await storage.delete(forKey: key3)
        try await storage.delete(forKey: key4)
        try await storage.delete(forKey: key5)
        try await storage.delete(forKey: key6)
        try await storage.delete(forKey: key7)
        try await storage.delete(forKey: key8)
        
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)
        fetched3 = try await storage.fetch(forKey: key3)
        fetched4 = try await storage.fetch(forKey: key4)
        fetched5 = try await storage.fetch(forKey: key5)
        fetched6 = try await storage.fetch(forKey: key6)
        fetched7 = try await storage.fetch(forKey: key7)
        fetched8 = try await storage.fetch(forKey: key8)
        
        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
        XCTAssertNil(fetched3)
        XCTAssertNil(fetched4)
        XCTAssertNil(fetched5)
        XCTAssertNil(fetched6)
        XCTAssertNil(fetched7)
        XCTAssertNil(fetched8)
        
        // When
        try await storage.set("newData1", forKey: key1)
        try await storage.set("newData2", forKey: key2)
        try await storage.set("newData3", forKey: key3)
        try await storage.set("newData4", forKey: key4)
        try await storage.set("newData5", forKey: key5)
        try await storage.set("newData6", forKey: key6)
        try await storage.set("newData7", forKey: key7)
        try await storage.set("newData8", forKey: key8)
        
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)
        fetched3 = try await storage.fetch(forKey: key3)
        fetched4 = try await storage.fetch(forKey: key4)
        fetched5 = try await storage.fetch(forKey: key5)
        fetched6 = try await storage.fetch(forKey: key6)
        fetched7 = try await storage.fetch(forKey: key7)
        fetched8 = try await storage.fetch(forKey: key8)
        
        // Then
        XCTAssertEqual(fetched1, "newData1")
        XCTAssertEqual(fetched2, "newData2")
        XCTAssertEqual(fetched3, "newData3")
        XCTAssertEqual(fetched4, "newData4")
        XCTAssertEqual(fetched5, "newData5")
        XCTAssertEqual(fetched6, "newData6")
        XCTAssertEqual(fetched7, "newData7")
        XCTAssertEqual(fetched8, "newData8")
        
        // When
        try await storage.set(nil, forKey: key1)
        try await storage.set(nil, forKey: key2)
        try await storage.set(nil, forKey: key3)
        try await storage.set(nil, forKey: key4)
        try await storage.set(nil, forKey: key5)
        try await storage.set(nil, forKey: key6)
        try await storage.set(nil, forKey: key7)
        try await storage.set(nil, forKey: key8)
        
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)
        fetched3 = try await storage.fetch(forKey: key3)
        fetched4 = try await storage.fetch(forKey: key4)
        fetched5 = try await storage.fetch(forKey: key5)
        fetched6 = try await storage.fetch(forKey: key6)
        fetched7 = try await storage.fetch(forKey: key7)
        fetched8 = try await storage.fetch(forKey: key8)
        
        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
        XCTAssertNil(fetched3)
        XCTAssertNil(fetched4)
        XCTAssertNil(fetched5)
        XCTAssertNil(fetched6)
        XCTAssertNil(fetched7)
        XCTAssertNil(fetched8)
        
        // When
        try await storage.save("newData1", forKey: key1)
        try await storage.save("newData2", forKey: key2)
        try await storage.save("newData3", forKey: key3)
        try await storage.save("newData4", forKey: key4)
        try await storage.save("newData5", forKey: key5)
        try await storage.save("newData6", forKey: key6)
        try await storage.save("newData7", forKey: key7)
        try await storage.save("newData8", forKey: key8)
        
        try await storage.clear(storage: KeychainStorage.self)
        
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)
        fetched3 = try await storage.fetch(forKey: key3)
        fetched4 = try await storage.fetch(forKey: key4)
        fetched5 = try await storage.fetch(forKey: key5)
        fetched6 = try await storage.fetch(forKey: key6)
        fetched7 = try await storage.fetch(forKey: key7)
        fetched8 = try await storage.fetch(forKey: key8)
        
        // Then
        XCTAssertEqual(fetched1, "newData1")
        XCTAssertEqual(fetched2, "newData2")
        XCTAssertEqual(fetched3, "newData3")
        XCTAssertEqual(fetched4, "newData4")
        XCTAssertEqual(fetched5, "newData5")
        XCTAssertEqual(fetched6, "newData6")
        XCTAssertEqual(fetched7, "newData7")
        XCTAssertEqual(fetched8, "newData8")
        
        // When
        try await storage.clear(storage: InMemoryStorage.self, forDomain: nil)
        
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)
        fetched3 = try await storage.fetch(forKey: key3)
        fetched4 = try await storage.fetch(forKey: key4)
        fetched5 = try await storage.fetch(forKey: key5)
        fetched6 = try await storage.fetch(forKey: key6)
        fetched7 = try await storage.fetch(forKey: key7)
        fetched8 = try await storage.fetch(forKey: key8)
        
        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
        XCTAssertEqual(fetched3, "newData3")
        XCTAssertEqual(fetched4, "newData4")
        XCTAssertEqual(fetched5, "newData5")
        XCTAssertEqual(fetched6, "newData6")
        XCTAssertEqual(fetched7, "newData7")
        XCTAssertEqual(fetched8, "newData8")
        
        // When
        try await storage.clear(storage: InMemoryStorage.self)
        
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)
        fetched3 = try await storage.fetch(forKey: key3)
        fetched4 = try await storage.fetch(forKey: key4)
        fetched5 = try await storage.fetch(forKey: key5)
        fetched6 = try await storage.fetch(forKey: key6)
        fetched7 = try await storage.fetch(forKey: key7)
        fetched8 = try await storage.fetch(forKey: key8)
        
        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
        XCTAssertNil(fetched3)
        XCTAssertNil(fetched4)
        XCTAssertEqual(fetched5, "newData5")
        XCTAssertEqual(fetched6, "newData6")
        XCTAssertEqual(fetched7, "newData7")
        XCTAssertEqual(fetched8, "newData8")
        
        // When
        try await storage.clear()
        
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)
        fetched3 = try await storage.fetch(forKey: key3)
        fetched4 = try await storage.fetch(forKey: key4)
        fetched5 = try await storage.fetch(forKey: key5)
        fetched6 = try await storage.fetch(forKey: key6)
        fetched7 = try await storage.fetch(forKey: key7)
        fetched8 = try await storage.fetch(forKey: key8)
        
        // Then
        XCTAssertNil(fetched1)
        XCTAssertNil(fetched2)
        XCTAssertNil(fetched3)
        XCTAssertNil(fetched4)
        XCTAssertNil(fetched5)
        XCTAssertNil(fetched6)
        XCTAssertNil(fetched7)
        XCTAssertNil(fetched8)
    }
    
    func testNonObservable() async throws {
        // Given
        var stoarge = UnifiedStorage(factory: DefaultUnifiedStorageFactory())
        
        // When
        var publisher = try await stoarge.publisher(forKey: InMemoryKey<String>(key: "key"))
        var stream = try await stoarge.stream(forKey: InMemoryKey<String>(key: "key"))
        
        // Then
        XCTAssertNil(publisher)
        XCTAssertNil(stream)
        
        // Given
        stoarge = UnifiedStorage(factory: ObservableUnifiedStorageFactory())
                
        // When
        publisher = try await stoarge.publisher(forKey: InMemoryKey<String>(key: "key"))
        stream = try await stoarge.stream(forKey: InMemoryKey<String>(key: "key"))

        // Then
        XCTAssertNotNil(publisher)
        XCTAssertNotNil(stream)
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
