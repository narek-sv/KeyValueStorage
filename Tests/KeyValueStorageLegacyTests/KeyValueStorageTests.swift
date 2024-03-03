//
//  KeyValueStorageTests.swift
//
//
//  Created by Narek Sahakyan on 7/27/22.
//

import XCTest
@testable import KeyValueStorageLegacy

#if os(macOS)
final class KeyValueStorageTests: XCTestCase {
    private var storage: KeyValueStorage!
    
    override func setUp() {
        storage = KeyValueStorage()
    }
    
    override func tearDown() {
        storage.clear()
    }
    
    // MARK: - Test native types
    
    func testInt() {
        // Given
        let integer = 17
        let key = KeyValueStorageKey<Int>(name: "anInteger")
        
        // When
        storage.save(integer, forKey: key)
        // Then
        XCTAssertEqual(integer, storage.fetch(forKey: key))
        
        // When
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testString() {
        // Given
        let string = "someString"
        let key = KeyValueStorageKey<String>(name: "aString")
        
        // When
        storage.save(string, forKey: key)
        // Then
        XCTAssertEqual(string, storage.fetch(forKey: key))
        
        // When
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testDate() {
        // Given
        let date = Date()
        let key = KeyValueStorageKey<Date>(name: "aDate")
        
        // When
        storage.save(date, forKey: key)
        // Then
        XCTAssertEqual(date, storage.fetch(forKey: key))
        
        // When
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testArray() {
        // Given
        let array = [1, 2, 3, 4]
        let key = KeyValueStorageKey<[Int]>(name: "anArray")
        
        // When
        storage.save(array, forKey: key)
        // Then
        XCTAssertEqual(array, storage.fetch(forKey: key))
        
        // When
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testDictionary1() {
        // Given
        let dictionary: [String: Int] = ["a": 1, "b": 2]
        let key = KeyValueStorageKey<[String: Int]>(name: "aDictionary")
        
        // When
        storage.save(dictionary, forKey: key)
        // Then
        XCTAssertEqual(dictionary, storage.fetch(forKey: key))
        
        // When
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testDictionary2() {
        // Given
        let dictionary: [Int: String] = [1: "a", 2: "b"]
        let key = KeyValueStorageKey<[Int: String]>(name: "aDictionary")
        
        // When
        storage.save(dictionary, forKey: key)
        // Then
        XCTAssertEqual(dictionary, storage.fetch(forKey: key))
        
        // When
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testIntInMemoryDefault() {
        // Given
        let integer = 17
        let key = KeyValueStorageKey<Int>(name: "anInteger", storage: .inMemory)
        let otherStorage = KeyValueStorage()
        
        // When
        storage.save(integer, forKey: key)
        // Then
        XCTAssertEqual(integer, storage.fetch(forKey: key))
        XCTAssertEqual(integer, otherStorage.fetch(forKey: key))
        
        // When
        otherStorage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testIntInMemoryDifferentWithGroup() {
        // Given
        let integer = 17
        let key = KeyValueStorageKey<Int>(name: "anInteger", storage: .inMemory)
        let otherStorage = KeyValueStorage(accessGroup: UUID().uuidString, teamID: "xxx")
        
        // When
        storage.save(integer, forKey: key)
        // Then
        XCTAssertEqual(integer, storage.fetch(forKey: key))
        XCTAssertNil(otherStorage.fetch(forKey: key))
        
        // When
        otherStorage.delete(forKey: key)
        // Then
        XCTAssertEqual(integer, storage.fetch(forKey: key))
    }
    
    func testIntInMemorySameWithGroup() {
        // Given
        let integer = 17
        let key = KeyValueStorageKey<Int>(name: "anInteger", storage: .inMemory)
        let otherStorage = KeyValueStorage(accessGroup: "accessGroup", teamID: "teamID")
        storage = KeyValueStorage(accessGroup: "accessGroup", teamID: "teamID")
        
        // When
        storage.save(integer, forKey: key)
        // Then
        XCTAssertEqual(integer, storage.fetch(forKey: key))
        XCTAssertEqual(integer, otherStorage.fetch(forKey: key))
        
        // When
        otherStorage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testIntSecure() {
        // Given
        let integer = 17
        let key = KeyValueStorageKey<Int>(name: "anInteger", storage: .keychain())
        
        // When
        storage.save(integer, forKey: key)
        // Then
        XCTAssertEqual(integer, storage.fetch(forKey: key))
        
        // When
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testStringSecure() {
        // Given
        let string = "someString"
        let key = KeyValueStorageKey<String>(name: "aString", storage: .keychain())
        
        // When
        storage.save(string, forKey: key)
        // Then
        XCTAssertEqual(string, storage.fetch(forKey: key))
        
        // When
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testDateSecure() {
        // Given
        let date = Date()
        let key = KeyValueStorageKey<Date>(name: "aDate", storage: .keychain())
        
        storage.save(date, forKey: key)
        // Then
        XCTAssertEqual(date, storage.fetch(forKey: key))
        
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testArraySecure() {
        // Given
        let array = [1, 2, 3, 4]
        let key = KeyValueStorageKey<[Int]>(name: "anArray", storage: .keychain())
        
        // When
        storage.save(array, forKey: key)
        // Then
        XCTAssertEqual(array, storage.fetch(forKey: key))
        
        // When
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testDictionary1Secure() {
        // Given
        let dictionary: [String: Int] = ["a": 1, "b": 2]
        let key = KeyValueStorageKey<[String: Int]>(name: "aDictionary", storage: .keychain())
        
        // When
        storage.save(dictionary, forKey: key)
        // Then
        XCTAssertEqual(dictionary, storage.fetch(forKey: key))
        
        // When
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testDictionary2Secure() {
        // Given
        let dictionary: [Int: String] = [1: "a", 2: "b"]
        let key = KeyValueStorageKey<[Int: String]>(name: "aDictionary", storage: .keychain())
        
        // When
        storage.save(dictionary, forKey: key)
        // Then
        XCTAssertEqual(dictionary, storage.fetch(forKey: key))
        
        // When
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    // MARK: - Test custom types
    
    func testStruct() {
        // Given
        let structure = SomeStruct(string: "struct", integer: 8, date: Date(timeIntervalSince1970: 44651))
        let key = KeyValueStorageKey<SomeStruct>(name: "aStruct")
        
        // When
        storage.save(structure, forKey: key)
        // Then
        XCTAssertEqual(structure, storage.fetch(forKey: key))
        
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testClass() {
        // Given
        let classification = SomeClass(double: 5.67, array: [8, 5], dict: ["some": "thing"])
        let key = KeyValueStorageKey<SomeClass>(name: "aClass")
        
        // When
        storage.save(classification, forKey: key)
        // Then
        XCTAssertEqual(classification, storage.fetch(forKey: key))
        XCTAssertFalse(classification === storage.fetch(forKey: key))
        // When
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testStructSecure() {
        // Given
        let structure = SomeStruct(string: "struct", integer: 8, date: Date(timeIntervalSince1970: 44651))
        let key = KeyValueStorageKey<SomeStruct>(name: "aStruct", storage: .keychain())
        
        // When
        storage.save(structure, forKey: key)
        // Then
        XCTAssertEqual(structure, storage.fetch(forKey: key))
        
        // When
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testClassSecure() {
        // Given
        let classification = SomeClass(double: 5.67, array: [8, 5], dict: ["some": "thing"])
        let key = KeyValueStorageKey<SomeClass>(name: "aClass", storage: .keychain())
        
        // When
        storage.save(classification, forKey: key)
        // Then
        XCTAssertEqual(classification, storage.fetch(forKey: key))
        XCTAssertFalse(classification === storage.fetch(forKey: key))
        // When
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    // MARK: - Testing edge cases
    
    func testWrongFetchType() {
        // Given
        let classification = SomeClass(double: 5.67, array: [8, 5], dict: ["some": "thing"])
        let key = KeyValueStorageKey<SomeClass>(name: "aClass")
        let wrongKey = KeyValueStorageKey<SomeStruct>(name: "aClass")
        
        // When
        storage.save(classification, forKey: key)
        // Then
        XCTAssertEqual(classification, storage.fetch(forKey: key))
        XCTAssertNil(storage.fetch(forKey: wrongKey))
        
        // When
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testWrongFetchSameKeyName() {
        // Given
        let classification = SomeClass(double: 5.67, array: [8, 5], dict: ["some": "thing"])
        let key = KeyValueStorageKey<SomeClass>(name: "aClass")
        let wrongKey = KeyValueStorageKey<SomeClass>(name: "aClass", storage: .keychain())
        
        // When
        storage.save(classification, forKey: key)
        // Then
        XCTAssertEqual(classification, storage.fetch(forKey: key))
        XCTAssertNil(storage.fetch(forKey: wrongKey))
        
        // When
        storage.delete(forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testWrongSave() {
        // Given
        let classification = SomeClass(double: .infinity, array: [8, 5], dict: ["some": "thing"])
        let key1 = KeyValueStorageKey<SomeClass>(name: "aClass")
        let key2 = KeyValueStorageKey<SomeClass>(name: "aClass", storage: .keychain())
        let key3 = KeyValueStorageKey<SomeClass>(name: "aClass", storage: .inMemory)

        // When
        storage.save(classification, forKey: key1)
        // Then
        XCTAssertNil(storage.fetch(forKey: key1))
        
        // When
        storage.save(classification, forKey: key2)
        // Then
        XCTAssertNil(storage.fetch(forKey: key2))
        
        // When
        storage.save(classification, forKey: key3)
        // Then
        XCTAssertEqual(classification, storage.fetch(forKey: key3))
    }
    
    func testSaveSameKeyName() {
        // Given
        let class1 = SomeClass(double: 5.67, array: [8, 5], dict: ["some": "thing"])
        let class2 = SomeClass(double: 6.67, array: [5, 8], dict: ["thing": "some"])
        let class3 = SomeClass(double: 8.88, array: [4, 3], dict: ["another": "stuff"])
        let class4 = SomeClass(double: 0, array: [0, 0], dict: ["zero": "empty"])
        let key1 = KeyValueStorageKey<SomeClass>(name: "aClass")
        let key2 = KeyValueStorageKey<SomeClass>(name: "aClass", storage: .keychain())
        let key3 = KeyValueStorageKey<SomeClass>(name: "aClass", storage: .inMemory)

        // When
        storage.save(class1, forKey: key1)
        // Then
        XCTAssertEqual(class1, storage.fetch(forKey: key1))
        
        // When
        storage.save(class2, forKey: key2)
        // Then
        XCTAssertEqual(class2, storage.fetch(forKey: key2))
        
        // When
        storage.save(class2, forKey: key2)
        // Then
        XCTAssertEqual(class2, storage.fetch(forKey: key2))
        
        // When
        storage.save(class3, forKey: key3)
        // Then
        XCTAssertEqual(class3, storage.fetch(forKey: key3))

        // When
        storage.save(class4, forKey: key1)
        // Then
        XCTAssertEqual(class4, storage.fetch(forKey: key1))
        XCTAssertNotEqual(class4, storage.fetch(forKey: key2))
        XCTAssertNotEqual(class4, storage.fetch(forKey: key3))
        
        // When
        storage.save(class4, forKey: key2)
        // Then
        XCTAssertEqual(class4, storage.fetch(forKey: key1))
        XCTAssertEqual(class4, storage.fetch(forKey: key2))
        XCTAssertNotEqual(class4, storage.fetch(forKey: key3))
        
        // When
        storage.save(class4, forKey: key3)
        // Then
        XCTAssertEqual(class4, storage.fetch(forKey: key1))
        XCTAssertEqual(class4, storage.fetch(forKey: key2))
        XCTAssertEqual(class4, storage.fetch(forKey: key3))
    }
    
    func testDeleteSameKeyName() {
        // Given
        let class1 = SomeClass(double: 5.67, array: [8, 5], dict: ["some": "thing"])
        let class2 = SomeClass(double: 6.67, array: [5, 8], dict: ["thing": "some"])
        let class3 = SomeClass(double: 8.88, array: [4, 3], dict: ["another": "stuff"])
        let key1 = KeyValueStorageKey<SomeClass>(name: "aClass")
        let key2 = KeyValueStorageKey<SomeClass>(name: "aClass", storage: .keychain())
        let key3 = KeyValueStorageKey<SomeClass>(name: "aClass", storage: .inMemory)

        // When
        storage.save(class1, forKey: key1)
        // Then
        XCTAssertEqual(class1, storage.fetch(forKey: key1))
        
        // When
        storage.save(class2, forKey: key2)
        // Then
        XCTAssertEqual(class2, storage.fetch(forKey: key2))
        
        // When
        storage.save(class3, forKey: key3)
        // Then
        XCTAssertEqual(class3, storage.fetch(forKey: key3))

        // When
        storage.delete(forKey: key1)
        // Then
        XCTAssertNil(storage.fetch(forKey: key1))
        XCTAssertNotNil(storage.fetch(forKey: key2))
        XCTAssertNotNil(storage.fetch(forKey: key3))
        
        // When
        storage.delete(forKey: key2)
        // Then
        XCTAssertNil(storage.fetch(forKey: key1))
        XCTAssertNil(storage.fetch(forKey: key2))
        XCTAssertNotNil(storage.fetch(forKey: key3))
        
        // When
        storage.delete(forKey: key3)
        // Then
        XCTAssertNil(storage.fetch(forKey: key1))
        XCTAssertNil(storage.fetch(forKey: key2))
        XCTAssertNil(storage.fetch(forKey: key3))
    }
    
    func testSet() {
        // Given
        let string = "someString"
        let key = KeyValueStorageKey<String>(name: "aString", storage: .keychain())
        
        // When
        storage.set(string, forKey: key)
        // Then
        XCTAssertEqual(string, storage.fetch(forKey: key))
        
        // When
        storage.set(nil, forKey: key)
        // Then
        XCTAssertNil(storage.fetch(forKey: key))
    }
    
    func testClear() {
        // Given
        let integer1 = 17
        let integer2 = 8
        let integer3 = 6
        let key1 = KeyValueStorageKey<Int>(name: "anInteger1", storage: .keychain())
        let key2 = KeyValueStorageKey<Int>(name: "anInteger2", storage: .userDefaults)
        let key3 = KeyValueStorageKey<Int>(name: "anInteger3", storage: .inMemory)

        storage.save(integer1, forKey: key1)
        storage.save(integer2, forKey: key2)
        storage.save(integer3, forKey: key3)

        XCTAssertEqual(integer1, storage.fetch(forKey: key1))
        XCTAssertEqual(integer2, storage.fetch(forKey: key2))
        XCTAssertEqual(integer3, storage.fetch(forKey: key3))

        // When
        storage.clear()
        
        // Then
        XCTAssertNil(storage.fetch(forKey: key1))
        XCTAssertNil(storage.fetch(forKey: key2))
        XCTAssertNil(storage.fetch(forKey: key3))
    }
    
    func testAccessGroup() {
        // Given
        let accessGroup = "group"
        XCTAssertNil(storage.accessGroup)
        
        // When
        storage = KeyValueStorage(accessGroup: accessGroup, teamID: "team")
        
        // Then
        XCTAssertEqual(accessGroup, storage.accessGroup)
    }
}

struct SomeStruct: Equatable, Codable {
    var string: String
    var integer: Int
    var date: Date
}

class SomeClass: Equatable, Codable {
    var double: Double
    var array: [Int]
    var dict: [String: String]
    
    init(double: Double, array: [Int], dict: [String: String]) {
        self.double = double
        self.array = array
        self.dict = dict
    }
    
    static func == (lhs: SomeClass, rhs: SomeClass) -> Bool {
        lhs.double == rhs.double && lhs.array == rhs.array && lhs.dict == rhs.dict
    }
}
#endif
