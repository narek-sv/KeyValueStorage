//
//  KeyValueStoragePropertyWrapperTests.swift
//
//
//  Created by Narek Sahakyan on 10.12.23.
//

import XCTest
@testable import KeyValueStorage

#if os(macOS)
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
final class KeyValueStoragePropertyWrapperTests: XCTestCase {
    private var storage: KeyValueStorage!
    
    override func setUp() {
        storage = KeyValueStorage()
    }
    
    override func tearDown() {
        storage.clear()
    }
        
    func testWrapper() {
        // Given
        let key = KeyValueStorageKey<Int>(name: "key", storage: .inMemory)
        
        // When
        @Storage(key: key) var int: Int?
        
        // Then
        XCTAssertNil(int)
        XCTAssertNil(storage.fetch(forKey: key))

        // When
        int = 10
        
        // Then
        XCTAssertEqual(int, 10)
        XCTAssertEqual(storage.fetch(forKey: key), 10)

        // When
        storage.save(13, forKey: key)
        
        // Then
        XCTAssertEqual(int, 13)
        XCTAssertEqual(storage.fetch(forKey: key), 13)
        
        // When
        storage.delete(forKey: key)
        
        // Then
        XCTAssertNil(int)
        XCTAssertNil(storage.fetch(forKey: key))
        
        // When
        storage.save(18, forKey: key)
        
        // Then
        XCTAssertEqual(int, 18)
        XCTAssertEqual(storage.fetch(forKey: key), 18)
        
        // When
        int = nil
        // Then
        XCTAssertNil(int)
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testPublishers() {
        // Given
        let key1 = KeyValueStorageKey<Int>(name: "key", storage: .inMemory)
        let key2 = KeyValueStorageKey<Int>(name: "key", storage: .inMemory)
        
        var sink1Called = false
        var sink2Called = false
        var sink3Called = false

        @Storage(key: key1) var int1: Int?
        @Storage(key: key2) var int2: Int?
        
        let subscription1 = $int1.sink { value in
            // Then
            XCTAssertEqual(int1, int2)
            XCTAssertEqual(int1, value)
            sink1Called = true
        }
        
        let subscription2 = $int2.sink { value in
            // Then
            XCTAssertEqual(int1, int2)
            XCTAssertEqual(value, int2)
            sink2Called = true
        }
        
        let subscription3 = $int2.sink { value in
            // Then
            XCTAssertEqual(int1, int2)
            XCTAssertEqual(value, int2)
            sink3Called = true
        }
        
        // When
        int1 = 10
        int2 = 20
        
        // Then
        XCTAssertEqual(int1, int2)
        XCTAssertTrue(sink1Called)
        XCTAssertTrue(sink2Called)
        XCTAssertTrue(sink3Called)
        XCTAssertNotNil(subscription1)
        XCTAssertNotNil(subscription2)
        XCTAssertNotNil(subscription3)
    }
}

#endif
