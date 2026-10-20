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
        await InMemoryStorage(scope: "other").clear()
        
        await UserDefaultsStorage().clear()
        try await UserDefaultsStorage(scope: "other").clear()
    }
    
    func testStorage() async throws {
        // Given
        let key1 = InMemoryKey<String>(key: "key1")
        let key2 = InMemoryKey<String>(key: "key2")
        let key3 = InMemoryKey<String>(key: "key3", scope: "other")
        let key4 = InMemoryKey<String>(key: "key4", scope: "other")
        let key5 = UserDefaultsKey<String>(key: "key1")
        let key6 = UserDefaultsKey<String>(key: "key2")
        let key7 = UserDefaultsKey<String>(key: "key3", scope: "other")
        let key8 = UserDefaultsKey<String>(key: "key4", scope: "other")
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
        
        try await storage.clear(storage: InMemoryStorage.self, forScope: nil)
        
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
        try await storage.clear(storage: InMemoryStorage.self, forScope: "other")
        
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
        try await storage.clear(storage: UserDefaultsStorage.self, forScope: nil)
        
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
        XCTAssertEqual(fetched7, "newData7")
        XCTAssertEqual(fetched8, "newData8")
        
        // When
        try await storage.clear(storage: UserDefaultsStorage.self, forScope: "other")
        
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
    
    func testClearStorageOnFreshInstance() async throws {
        // Given
        let key = InMemoryKey<String>(key: "key", scope: "other")
        try await UnifiedStorage().save("value", forKey: key)
        
        // When
        try await UnifiedStorage().clear(storage: InMemoryStorage.self, forScope: "other")
        
        // Then
        let fetched = try await UnifiedStorage().fetch(forKey: key)
        XCTAssertNil(fetched)
    }
    
    func testFactoriesUseTheGivenCoder() async throws {
        for makeFactory in [{ DefaultUnifiedStorageFactory(coder: $0) }, { ObservableUnifiedStorageFactory(coder: $0) }] as [(DataCoder) -> DefaultUnifiedStorageFactory] {
            // Given
            let coder = CountingCoder()
            let storage = UnifiedStorage(factory: makeFactory(coder))
            let key = InMemoryKey<Int>(key: "coder")
            
            // When
            try await storage.save(42, forKey: key)
            let fetched = try await storage.fetch(forKey: key)
            
            // Then
            XCTAssertEqual(fetched, 42)
            XCTAssertEqual(coder.encodeCalls, 1)
            XCTAssertEqual(coder.decodeCalls, 1)
            try await storage.delete(forKey: key)
        }
    }
    
    func testFactoriesUseRawDataCoderByDefault() async throws {
        for factory in [DefaultUnifiedStorageFactory(), ObservableUnifiedStorageFactory()] {
            // Given
            let storage = UnifiedStorage(factory: factory)
            let underlyingStorage = await InMemoryStorage(scope: "factoryCoder")
            
            // When
            try await storage.save(Data([0xAA]), forKey: InMemoryKey<Data>(key: "data", scope: "factoryCoder"))
            
            // Then
            let stored = await underlyingStorage.fetch(forKey: "data")
            XCTAssertEqual(stored, Data([0xAA]))
            await underlyingStorage.clear()
        }
    }
    
    func testKeyHashing() {
        // Given
        let key = InMemoryKey<String>(key: "key", scope: "scope")
        let differentKeys: [AnyHashable] = [
            InMemoryKey<String>(key: "other", scope: "scope"),
            InMemoryKey<String>(key: "key", scope: "other"),
            InMemoryKey<String>(key: "key"),
            InMemoryKey<Int>(key: "key", scope: "scope"),
            UserDefaultsKey<String>(key: "key", scope: "scope")
        ]
        
        // When
        let set = Set([AnyHashable(key), AnyHashable(InMemoryKey<String>(key: "key", scope: "scope"))] + differentKeys)
        
        // Then
        XCTAssertEqual(key, InMemoryKey<String>(key: "key", scope: "scope"))
        XCTAssertEqual(key.hashValue, InMemoryKey<String>(key: "key", scope: "scope").hashValue)
        XCTAssertEqual(set.count, differentKeys.count + 1)
    }
    
    func testConcurrentFirstAccessCreatesStorageOnce() async throws {
        // Given
        let factory = CountingUnifiedStorageFactory()
        let storage = UnifiedStorage(factory: factory)
        let key = InMemoryKey<Int>(key: "key")
        
        // When
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<64 {
                group.addTask { _ = try await storage.fetch(forKey: key) }
            }
            
            try await group.waitForAll()
        }
        
        // Then
        XCTAssertEqual(factory.dataStorageCalls, 1)
    }
    
    func testFailedStorageCreationIsRetried() async throws {
        // Given
        let factory = CountingUnifiedStorageFactory(failures: 1)
        let storage = UnifiedStorage(factory: factory)
        let key = InMemoryKey<Int>(key: "key")
        
        do {
            // When
            _ = try await storage.fetch(forKey: key)
            XCTFail("Expected error")
        } catch {
            // Then
            XCTAssertEqual(error as? CocoaError, CocoaError(.featureUnsupported))
        }
        
        // When
        let fetched = try await storage.fetch(forKey: key)
        
        // Then
        XCTAssertNil(fetched)
        XCTAssertEqual(factory.dataStorageCalls, 2)
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

/// Counts how often it encodes and decodes.
final class CountingCoder: DataCoder, @unchecked Sendable {
    private(set) var encodeCalls = 0
    private(set) var decodeCalls = 0
    private let coder = JSONDataCoder()
    
    func encode<Value: CodingValue>(_ value: Value) async throws -> Data {
        encodeCalls += 1
        return try coder.encode(value)
    }
    
    func decode<Value: CodingValue>(_ data: Data) async throws -> Value {
        decodeCalls += 1
        return try coder.decode(data)
    }
}

/// Creates storages slowly, like a storage that opens a database, and can fail the first calls.
final class CountingUnifiedStorageFactory: DefaultUnifiedStorageFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var failures: Int
    private var calls = 0
    
    var dataStorageCalls: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
    
    init(failures: Int = 0) {
        self.failures = failures
    }
    
    override func dataStorage<Storage: KeyValueDataStorage>(for scope: Storage.Scope?) async throws -> Storage {
        let shouldFail = registerCall()
        try await Task.sleep(nanoseconds: 10_000_000)
        if shouldFail {
            throw CocoaError(.featureUnsupported)
        }
        
        return try await super.dataStorage(for: scope)
    }
    
    /// Returns whether this call should fail.
    private func registerCall() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        failures -= 1
        return failures >= 0
    }
}

final class MockedUnifiedStorageFactory: DefaultUnifiedStorageFactory, @unchecked Sendable {
    override func dataStorage<Storage: KeyValueDataStorage>(for scope: Storage.Scope?) async throws -> Storage {
        switch Storage.self {
        case is InMemoryMock.Type:
            if let scope = scope as? InMemoryStorage.Scope {
                return await InMemoryMock(scope: scope) as! Storage
            } else {
                return await InMemoryMock() as! Storage
            }
        default:
            return try await super.dataStorage(for: scope)
        }
    }
}
