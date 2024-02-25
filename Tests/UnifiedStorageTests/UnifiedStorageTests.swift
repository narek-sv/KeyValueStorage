//
//  UnifiedStorageTests.swift
//
//
//  Created by Narek Sahakyan on 12.12.23.
//

import XCTest
import Foundation
@testable import UnifiedStorage

//@UserDefaultsActor
//final class UnifiedStorageTests: XCTestCase {
//    static let Storage = UserDefaultsStorage.self
//    
//    func testInMemoryDomain() async throws {
//        // Given
//        let storage1 = try Self.Storage.init()
//        let storage2 = try Self.Storage.init(domain: "other")
//        
//        // When - Then
//        XCTAssertEqual(storage1.domain, nil)
//        XCTAssertEqual(storage2.domain, "other")
//    }
//    
//    func testInMemoryFetch() async throws {
//        // Given
//        let storage = try Self.Storage.init()
//        let data1 = Data([0xAA, 0xBB, 0xCC])
//        let data2 = Data([0xDD, 0xEE, 0xFF])
//        let key1 = "key1"
//        let key2 = "key2"
//        InMemoryStorage.container = [:]
//        
//        // When
//        var fetched1 = try await storage.fetch(forKey: key1)
//        var fetched2 = try await storage.fetch(forKey: key2)
//
//        // Then
//        XCTAssertNil(fetched1)
//        XCTAssertNil(fetched2)
//
//        // When
//        InMemoryStorage.container = [nil: [key1: data1]]
//        fetched1 = try await storage.fetch(forKey: key1)
//        fetched2 = try await storage.fetch(forKey: key2)
//
//        // Then
//        XCTAssertEqual(fetched1, data1)
//        XCTAssertNil(fetched2)
//
//        // When
//        InMemoryStorage.container = [nil: [key1: data2]]
//        fetched1 = try await storage.fetch(forKey: key1)
//        fetched2 = try await storage.fetch(forKey: key2)
//
//        // Then
//        XCTAssertEqual(fetched1, data2)
//        XCTAssertNil(fetched2)
//        
//        // When
//        InMemoryStorage.container = [nil: [key1: data1, key2: data2]]
//        fetched1 = try await storage.fetch(forKey: key1)
//        fetched2 = try await storage.fetch(forKey: key2)
//
//        // Then
//        XCTAssertEqual(fetched1, data1)
//        XCTAssertEqual(fetched2, data2)
//        
//        // When
//        InMemoryStorage.container = [nil: [key2: data1]]
//        fetched1 = try await storage.fetch(forKey: key1)
//        fetched2 = try await storage.fetch(forKey: key2)
//
//        // Then
//        XCTAssertNil(fetched1)
//        XCTAssertEqual(fetched2, data1)
//        
//        // When
//        InMemoryStorage.container = [nil: [:]]
//        fetched1 = try await storage.fetch(forKey: key1)
//        fetched2 = try await storage.fetch(forKey: key2)
//
//        // Then
//        XCTAssertNil(fetched1)
//        XCTAssertNil(fetched2)
//    }
//    
//    func testInMemoryFetchDifferentDomains() async throws {
//        // Given
//        let storage1 = try Self.Storage.init()
//        let storage2 = try Self.Storage.init(domain: "other")
//        let data1 = Data([0xAA, 0xBB, 0xCC])
//        let data2 = Data([0xDD, 0xEE, 0xFF])
//        let key = "key"
//        InMemoryStorage.container = [:]
//        
//        // When
//        var fetched1 = try await storage1.fetch(forKey: key)
//        var fetched2 = try await storage2.fetch(forKey: key)
//
//        // Then
//        XCTAssertNil(fetched1)
//        XCTAssertNil(fetched2)
//
//        // When
//        InMemoryStorage.container = [nil: [key: data1]]
//        fetched1 = try await storage1.fetch(forKey: key)
//        fetched2 = try await storage2.fetch(forKey: key)
//
//        // Then
//        XCTAssertEqual(fetched1, data1)
//        XCTAssertNil(fetched2)
//
//        // When
//        InMemoryStorage.container = ["other": [key: data2]]
//        fetched1 = try await storage1.fetch(forKey: key)
//        fetched2 = try await storage2.fetch(forKey: key)
//
//        // Then
//        XCTAssertNil(fetched1)
//        XCTAssertEqual(fetched2, data2)
//
//        // When
//        InMemoryStorage.container = [nil: [key: data2]]
//        fetched1 = try await storage1.fetch(forKey: key)
//        fetched2 = try await storage2.fetch(forKey: key)
//
//        // Then
//        XCTAssertEqual(fetched1, data2)
//        XCTAssertNil(fetched2)
//
//        // When
//        InMemoryStorage.container = [nil: [key: data1], "other": [key: data2]]
//        fetched1 = try await storage1.fetch(forKey: key)
//        fetched2 = try await storage2.fetch(forKey: key)
//
//        // Then
//        XCTAssertEqual(fetched1, data1)
//        XCTAssertEqual(fetched2, data2)
//        
//        // When
//        InMemoryStorage.container = [nil: [:], "other": [:]]
//        fetched1 = try await storage1.fetch(forKey: key)
//        fetched2 = try await storage2.fetch(forKey: key)
//
//        // Then
//        XCTAssertNil(fetched1)
//        XCTAssertNil(fetched2)
//    }
//    
//    func testInMemorySave() async throws {
//        // Given
//        let storage = try Self.Storage.init()
//        let data1 = Data([0xAA, 0xBB, 0xCC])
//        let data2 = Data([0xDD, 0xEE, 0xFF])
//        let key1 = "key1"
//        let key2 = "key2"
//        InMemoryStorage.container = [:]
//        
//        // When
//        try await storage.save(data1, forKey: key1)
//
//        // Then
//        XCTAssertEqual(InMemoryStorage.container[nil]?[key1], data1)
//        XCTAssertNil(InMemoryStorage.container[nil]?[key2])
//
//        // When
//        try await storage.save(data2, forKey: key1)
//
//        // Then
//        XCTAssertEqual(InMemoryStorage.container[nil]?[key1], data2)
//        XCTAssertNil(InMemoryStorage.container[nil]?[key2])
//
//        // When
//        try await storage.save(data1, forKey: key2)
//        
//        // Then
//        XCTAssertEqual(InMemoryStorage.container[nil]?[key1], data2)
//        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data1)
//    }
//    
//    func testInMemorySaveDifferentDomains() async throws {
//        // Given
//        let storage1 = try Self.Storage.init()
//        let storage2 = try Self.Storage.init(domain: "other")
//        let data1 = Data([0xAA, 0xBB, 0xCC])
//        let data2 = Data([0xDD, 0xEE, 0xFF])
//        let key = "key"
//        InMemoryStorage.container = [:]
//        
//        // When
//        try await storage1.save(data1, forKey: key)
//
//        // Then
//        XCTAssertEqual(InMemoryStorage.container[nil]?[key], data1)
//        XCTAssertNil(InMemoryStorage.container["other"]?[key])
//
//        // When
//        try await storage2.save(data2, forKey: key)
//
//        // Then
//        XCTAssertEqual(InMemoryStorage.container[nil]?[key], data1)
//        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)
//
//        // When
//        try await storage1.save(data2, forKey: key)
//        
//        // Then
//        XCTAssertEqual(InMemoryStorage.container[nil]?[key], data2)
//        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)
//    }
//    
//    func testInMemoryDelete() async throws {
//        // Given
//        let storage = try Self.Storage.init()
//        let data1 = Data([0xAA, 0xBB, 0xCC])
//        let data2 = Data([0xDD, 0xEE, 0xFF])
//        let key1 = "key1"
//        let key2 = "key2"
//        InMemoryStorage.container = [nil: [key1: data1, key2: data2]]
//        
//        // When
//        try await storage.delete(forKey: key1)
//
//        // Then
//        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
//        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data2)
//
//        // When
//        try await storage.delete(forKey: key1)
//
//        // Then
//        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
//        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data2)
//
//        // When
//        try await storage.delete(forKey: key2)
//
//        // Then
//        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
//        XCTAssertNil(InMemoryStorage.container[nil]?[key2])
//    }
//    
//    func testInMemoryDeleteDifferentDomains() async throws {
//        // Given
//        let storage1 = try Self.Storage.init()
//        let storage2 = try Self.Storage.init(domain: "other")
//        let data1 = Data([0xAA, 0xBB, 0xCC])
//        let data2 = Data([0xDD, 0xEE, 0xFF])
//        let key = "key"
//        InMemoryStorage.container = [nil: [key: data1], "other": [key: data2]]
//        
//        // When
//        try await storage1.delete(forKey: key)
//
//        // Then
//        XCTAssertNil(InMemoryStorage.container[nil]?[key])
//        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)
//
//        // When
//        try await storage1.delete(forKey: key)
//
//        // Then
//        XCTAssertNil(InMemoryStorage.container[nil]?[key])
//        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)
//
//        // When
//        try await storage2.delete(forKey: key)
//
//        // Then
//        XCTAssertNil(InMemoryStorage.container[nil]?[key])
//        XCTAssertNil(InMemoryStorage.container["other"]?[key])
//    }
//    
//    func testInMemorySet() async throws {
//        // Given
//        let storage = try Self.Storage.init()
//        let data1 = Data([0xAA, 0xBB, 0xCC])
//        let data2 = Data([0xDD, 0xEE, 0xFF])
//        let key1 = "key1"
//        let key2 = "key2"
//        InMemoryStorage.container = [nil: [key1: data1, key2: data2]]
//        
//        // When
//        try await storage.set(data2, forKey: key1)
//
//        // Then
//        XCTAssertEqual(InMemoryStorage.container[nil]?[key1], data2)
//        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data2)
//
//        // When
//        try await storage.set(nil, forKey: key1)
//
//        // Then
//        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
//        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data2)
//        
//        // When
//        try await storage.set(data1, forKey: key2)
//
//        // Then
//        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
//        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data1)
//        
//        // When
//        try await storage.set(nil, forKey: key2)
//
//        // Then
//        XCTAssertNil(InMemoryStorage.container[nil]?[key1])
//        XCTAssertNil(InMemoryStorage.container[nil]?[key2])
//    }
//    
//    func testInMemorySetDifferentDomains() async throws {
//        // Given
//        let storage1 = try Self.Storage.init()
//        let storage2 = try Self.Storage.init(domain: "other")
//        let data1 = Data([0xAA, 0xBB, 0xCC])
//        let data2 = Data([0xDD, 0xEE, 0xFF])
//        let key = "key"
//        InMemoryStorage.container = [nil: [key: data1], "other": [key: data2]]
//        
//        // When
//        try await storage1.set(data2, forKey: key)
//
//        // Then
//        XCTAssertEqual(InMemoryStorage.container[nil]?[key], data2)
//        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)
//
//        // When
//        try await storage1.set(nil, forKey: key)
//
//        // Then
//        XCTAssertNil(InMemoryStorage.container[nil]?[key])
//        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data2)
//        
//        // When
//        try await storage2.set(data1, forKey: key)
//
//        // Then
//        XCTAssertNil(InMemoryStorage.container[nil]?[key])
//        XCTAssertEqual(InMemoryStorage.container["other"]?[key], data1)
//
//        // When
//        try await storage2.set(nil, forKey: key)
//
//        // Then
//        XCTAssertNil(InMemoryStorage.container[nil]?[key])
//        XCTAssertNil(InMemoryStorage.container["other"]?[key])
//    }
//    
//    func testInMemoryClear() async throws {
//        // Given
//        let storage1 = try Self.Storage.init()
//        let storage2 = try Self.Storage.init(domain: "other")
//        let data1 = Data([0xAA, 0xBB, 0xCC])
//        let data2 = Data([0xDD, 0xEE, 0xFF])
//        let key1 = "key1"
//        let key2 = "key2"
//        InMemoryStorage.container = [nil: [key1: data1, key2: data2], "other": [key1: data2, key2: data1]]
//        
//        // When
//        try await storage1.clear()
//
//        // Then
//        XCTAssertEqual(InMemoryStorage.container[nil], [:])
//        XCTAssertEqual(InMemoryStorage.container["other"]?[key1], data2)
//        XCTAssertEqual(InMemoryStorage.container["other"]?[key2], data1)
//
//        // When
//        try await storage1.clear()
//
//        // Then
//        XCTAssertEqual(InMemoryStorage.container[nil], [:])
//        XCTAssertEqual(InMemoryStorage.container["other"]?[key1], data2)
//        XCTAssertEqual(InMemoryStorage.container["other"]?[key2], data1)
//        
//        // When
//        InMemoryStorage.container = [nil: [key1: data1, key2: data2], "other": [key1: data2, key2: data1]]
//        try await storage2.clear()
//
//        // Then
//        XCTAssertEqual(InMemoryStorage.container[nil]?[key1], data1)
//        XCTAssertEqual(InMemoryStorage.container[nil]?[key2], data2)
//        XCTAssertEqual(InMemoryStorage.container["other"], [:])
//
//
//        // When
//        try await storage1.clear()
//
//        // Then
//        XCTAssertEqual(InMemoryStorage.container[nil], [:])
//        XCTAssertEqual(InMemoryStorage.container["other"], [:])
//    }
//}
