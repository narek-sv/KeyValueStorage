//
//  KeyValueCodingStorageTests.swift
//
//
//  Created by Narek Sahakyan on 01.03.24.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class KeyValueCodingStorageTests: XCTestCase {
    var underlyingStorage: InMemoryStorage!
    var storage: KeyValueCodingStorage<InMemoryStorage>!
    var coder: DataCoder!

    @InMemoryActor
    override func setUp() async throws {
        underlyingStorage = InMemoryStorage()
        coder = JSONDataCoder()

        storage = await .init(storage: underlyingStorage, coder: coder)
        
        InMemoryStorage.container = [nil: [:]]
    }
    
    @InMemoryActor
    func testFetch() async throws {
        // Given
        let instance1 = CustomStruct(int: 3, string: "3", date: Date(timeIntervalSince1970: 3), inner: [Inner(id: .init())])
        let instance2 = CustomClass(int: 4, string: "4", date: Date(timeIntervalSince1970: 4), inner: [Inner(id: .init())])
        let instance3 = CustomActor(int: 5, string: "4", date: Date(timeIntervalSince1970: 5), inner: [Inner(id: .init())])
        let instance4 = CustomEnum.case1(6)

        let key1 = KeyValueCodingStorageKey<InMemoryStorage, CustomStruct>(key: "key1")
        let key2 = KeyValueCodingStorageKey<InMemoryStorage, CustomClass>(key: "key2")
        let key3 = KeyValueCodingStorageKey<InMemoryStorage, CustomActor>(key: "key3")
        let key4 = KeyValueCodingStorageKey<InMemoryStorage, CustomEnum>(key: "key4")

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

        // Given
        InMemoryStorage.container = [nil: [
            "key1": try await coder.encode(instance1),
            "key2": try await coder.encode(instance2),
            "key3": try await coder.encode(instance3),
            "key4": try await coder.encode(instance4)
        ]]
        
        // When
        fetched1 = try await storage.fetch(forKey: key1)
        fetched2 = try await storage.fetch(forKey: key2)
        fetched3 = try await storage.fetch(forKey: key3)
        fetched4 = try await storage.fetch(forKey: key4)
        
        // Then
        XCTAssertEqual(fetched1, instance1)
        XCTAssertEqual(fetched2, instance2)
        XCTAssertEqual(fetched3, instance3)
        XCTAssertEqual(fetched4, instance4)
    }
    
    @InMemoryActor
    func testSave() async throws {
        // Given
        let instance1 = CustomStruct(int: 3, string: "3", date: Date(timeIntervalSince1970: 3), inner: [Inner(id: .init())])
        let instance2 = CustomClass(int: 4, string: "4", date: Date(timeIntervalSince1970: 4), inner: [Inner(id: .init())])
        let instance3 = CustomActor(int: 5, string: "4", date: Date(timeIntervalSince1970: 5), inner: [Inner(id: .init())])
        let instance4 = CustomEnum.case1(6)

        let key1 = KeyValueCodingStorageKey<InMemoryStorage, CustomStruct>(key: "key1")
        let key2 = KeyValueCodingStorageKey<InMemoryStorage, CustomClass>(key: "key2")
        let key3 = KeyValueCodingStorageKey<InMemoryStorage, CustomActor>(key: "key3")
        let key4 = KeyValueCodingStorageKey<InMemoryStorage, CustomEnum>(key: "key4")

        // When
        try await storage.save(instance1, forKey: key1)
        try await storage.save(instance2, forKey: key2)
        try await storage.save(instance3, forKey: key3)
        try await storage.save(instance4, forKey: key4)
        
        // Then
        let decoded1: CustomStruct = try await coder.decode(InMemoryStorage.container[nil]!["key1"]!)
        let decoded2: CustomClass = try await coder.decode(InMemoryStorage.container[nil]!["key2"]!)
        let decoded3: CustomActor = try await coder.decode(InMemoryStorage.container[nil]!["key3"]!)
        let decoded4: CustomEnum = try await coder.decode(InMemoryStorage.container[nil]!["key4"]!)

        XCTAssertEqual(decoded1, instance1)
        XCTAssertEqual(decoded2, instance2)
        XCTAssertEqual(decoded3, instance3)
        XCTAssertEqual(decoded4, instance4)
    }
    
    @InMemoryActor
    func testDelete() async throws {
        // Given
        let instance1 = CustomStruct(int: 3, string: "3", date: Date(timeIntervalSince1970: 3), inner: [Inner(id: .init())])
        let instance2 = CustomClass(int: 4, string: "4", date: Date(timeIntervalSince1970: 4), inner: [Inner(id: .init())])
        let instance3 = CustomActor(int: 5, string: "4", date: Date(timeIntervalSince1970: 5), inner: [Inner(id: .init())])
        let instance4 = CustomEnum.case1(6)

        let key1 = KeyValueCodingStorageKey<InMemoryStorage, CustomStruct>(key: "key1")
        let key2 = KeyValueCodingStorageKey<InMemoryStorage, CustomClass>(key: "key2")
        let key3 = KeyValueCodingStorageKey<InMemoryStorage, CustomActor>(key: "key3")
        let key4 = KeyValueCodingStorageKey<InMemoryStorage, CustomEnum>(key: "key4")

        InMemoryStorage.container = [nil: [
            "key1": try await coder.encode(instance1),
            "key2": try await coder.encode(instance2),
            "key3": try await coder.encode(instance3),
            "key4": try await coder.encode(instance4)
        ]]
        
        // When
        try await storage.delete(forKey: key1)
        try await storage.delete(forKey: key2)
        try await storage.delete(forKey: key3)
        try await storage.delete(forKey: key4)
        
        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?["key1"])
        XCTAssertNil(InMemoryStorage.container[nil]?["key2"])
        XCTAssertNil(InMemoryStorage.container[nil]?["key3"])
        XCTAssertNil(InMemoryStorage.container[nil]?["key4"])
    }
    
    @InMemoryActor
    func testSet() async throws {
        // Given
        let instance1 = CustomStruct(int: 3, string: "3", date: Date(timeIntervalSince1970: 3), inner: [Inner(id: .init())])
        let instance2 = CustomClass(int: 4, string: "4", date: Date(timeIntervalSince1970: 4), inner: [Inner(id: .init())])
        let instance3 = CustomActor(int: 5, string: "4", date: Date(timeIntervalSince1970: 5), inner: [Inner(id: .init())])
        let instance4 = CustomEnum.case1(6)

        let key1 = KeyValueCodingStorageKey<InMemoryStorage, CustomStruct>(key: "key1")
        let key2 = KeyValueCodingStorageKey<InMemoryStorage, CustomClass>(key: "key2")
        let key3 = KeyValueCodingStorageKey<InMemoryStorage, CustomActor>(key: "key3")
        let key4 = KeyValueCodingStorageKey<InMemoryStorage, CustomEnum>(key: "key4")

        InMemoryStorage.container = [nil: [
            "key1": try await coder.encode(instance1),
            "key2": try await coder.encode(instance2),
            "key3": try await coder.encode(instance3),
            "key4": try await coder.encode(instance4)
        ]]
        
        // When
        try await storage.set(nil, forKey: key1)
        try await storage.set(nil, forKey: key2)
        try await storage.set(nil, forKey: key3)
        try await storage.set(nil, forKey: key4)
        
        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?["key1"])
        XCTAssertNil(InMemoryStorage.container[nil]?["key2"])
        XCTAssertNil(InMemoryStorage.container[nil]?["key3"])
        XCTAssertNil(InMemoryStorage.container[nil]?["key4"])
        
        // When
        try await storage.set(instance1, forKey: key1)
        try await storage.set(instance2, forKey: key2)
        try await storage.set(instance3, forKey: key3)
        try await storage.set(instance4, forKey: key4)
        
        // Then
        let decoded1: CustomStruct = try await coder.decode(InMemoryStorage.container[nil]!["key1"]!)
        let decoded2: CustomClass = try await coder.decode(InMemoryStorage.container[nil]!["key2"]!)
        let decoded3: CustomActor = try await coder.decode(InMemoryStorage.container[nil]!["key3"]!)
        let decoded4: CustomEnum = try await coder.decode(InMemoryStorage.container[nil]!["key4"]!)

        XCTAssertEqual(decoded1, instance1)
        XCTAssertEqual(decoded2, instance2)
        XCTAssertEqual(decoded3, instance3)
        XCTAssertEqual(decoded4, instance4)
    }
    
    @InMemoryActor
    func testClear() async throws {
        // Given
        let instance1 = CustomStruct(int: 3, string: "3", date: Date(timeIntervalSince1970: 3), inner: [Inner(id: .init())])
        let instance2 = CustomClass(int: 4, string: "4", date: Date(timeIntervalSince1970: 4), inner: [Inner(id: .init())])
        let instance3 = CustomActor(int: 5, string: "4", date: Date(timeIntervalSince1970: 5), inner: [Inner(id: .init())])
        let instance4 = CustomEnum.case1(6)
        
        InMemoryStorage.container = [nil: [
            "key1": try await coder.encode(instance1),
            "key2": try await coder.encode(instance2),
            "key3": try await coder.encode(instance3),
            "key4": try await coder.encode(instance4)
        ]]
        
        // When
        try await storage.clear()
        
        // Then
        XCTAssertNil(InMemoryStorage.container[nil]?["key1"])
        XCTAssertNil(InMemoryStorage.container[nil]?["key2"])
        XCTAssertNil(InMemoryStorage.container[nil]?["key3"])
        XCTAssertNil(InMemoryStorage.container[nil]?["key4"])
    }
    
}

extension KeyValueCodingStorageTests {
    struct CustomStruct: Codable, Equatable {
        let int: Int
        let string: String
        let date: Date
        let inner: [Inner]
    }
    
    class CustomClass: Codable, Equatable {
        let int: Int
        let string: String
        let date: Date
        let inner: [Inner]
        
        init(int: Int, string: String, date: Date, inner: [Inner]) {
            self.int = int
            self.string = string
            self.date = date
            self.inner = inner
        }
        
        static func == (lhs: CustomClass, rhs: CustomClass) -> Bool {
            lhs.int == rhs.int &&
            lhs.string == rhs.string &&
            lhs.date == rhs.date &&
            lhs.inner == rhs.inner
        }
    }
    
    actor CustomActor: Codable, Equatable {
        let int: Int
        let string: String
        let date: Date
        let inner: [Inner]
        
        init(int: Int, string: String, date: Date, inner: [Inner]) {
            self.int = int
            self.string = string
            self.date = date
            self.inner = inner
        }
        
        static func == (lhs: CustomActor, rhs: CustomActor) -> Bool {
            lhs.int == rhs.int &&
            lhs.string == rhs.string &&
            lhs.date == rhs.date &&
            lhs.inner == rhs.inner
        }
        
        init(from decoder: Decoder) throws {
            let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
            self.int = try container.decode(Int.self, forKey: .int)
            self.string = try container.decode(String.self, forKey: .string)
            self.date = try container.decode(Date.self, forKey: .date)
            self.inner = try container.decode([Inner].self, forKey: .inner)
        }
        
        nonisolated func encode(to encoder: Encoder) throws {
            var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.int, forKey: .int)
            try container.encode(self.string, forKey: .string)
            try container.encode(self.date, forKey: .date)
            try container.encode(self.inner, forKey: .inner)
        }
        
        enum CodingKeys: CodingKey {
            case int
            case string
            case date
            case inner
        }
    }
    
    enum CustomEnum: Codable, Equatable {
        case case1(Int)
        case case2(String)
        case case3(date: Date)
    }
    
    struct Inner: Codable, Equatable {
        let id: UUID
    }
}
