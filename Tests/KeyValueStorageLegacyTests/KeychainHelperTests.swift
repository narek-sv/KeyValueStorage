//
//  KeychainHelperTests.swift
//  
//
//  Created by Narek Sahakyan on 7/28/22.
//

import XCTest
@testable import KeyValueStorageLegacy

#if os(macOS)
class KeychainHelperTests: XCTestCase {
    private var helper: KeychainHelper!
    
    override func setUp() {
        helper = KeychainHelper(serviceName: "asd")
    }
    
    override func tearDown() {
        helper.removeAll()
    }

    func testMain() throws {
        // Given
        let data = "secret".data(using: .utf8)!
        let newData = "new".data(using: .utf8)!
        let key = "key"
        
        // When - Then
        XCTAssertNil(helper.get(forKey: key))
        XCTAssertNil(helper.get(forKey: key, withAccessibility: .whenUnlocked))
        XCTAssertNil(helper.get(forKey: key, isSynchronizable: true))

        // When
        XCTAssertTrue(helper.set(data, forKey: key))
        
        // Then
        XCTAssertEqual(helper.get(forKey: key), data)
        XCTAssertEqual(helper.get(forKey: key, withAccessibility: .whenUnlocked), data)
        XCTAssertNil(helper.get(forKey: key, isSynchronizable: true))
        
        // When
        XCTAssertTrue(helper.set(newData, forKey: key))

        // Then
        XCTAssertEqual(helper.get(forKey: key), newData)
        XCTAssertEqual(helper.get(forKey: key, withAccessibility: .whenUnlocked), newData)
        XCTAssertNil(helper.get(forKey: key, isSynchronizable: true))
        
        // When
        XCTAssertTrue(helper.remove(forKey: key))
        
        // Then
        XCTAssertNil(helper.get(forKey: key))
        XCTAssertNil(helper.get(forKey: key, withAccessibility: .whenUnlocked))
        XCTAssertNil(helper.get(forKey: key, isSynchronizable: true))
        
        // When
        XCTAssertFalse(helper.set(data, forKey: key, isSynchronizable: true))
        
        // Then
        XCTAssertNil(helper.get(forKey: key))
        XCTAssertNil(helper.get(forKey: key, withAccessibility: .whenUnlocked))
        XCTAssertNil(helper.get(forKey: key, withAccessibility: .afterFirstUnlock))
        XCTAssertNil(helper.get(forKey: key, isSynchronizable: true))
    }
    
    func testAccessibilityRawValues() {
        // Given
        XCTAssertEqual(KeychainAccessibility.afterFirstUnlock.key, String(kSecAttrAccessibleAfterFirstUnlock))
        XCTAssertEqual(KeychainAccessibility.afterFirstUnlockThisDeviceOnly.key, String(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly))
        XCTAssertEqual(KeychainAccessibility.whenPasscodeSetThisDeviceOnly.key, String(kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly))
        XCTAssertEqual(KeychainAccessibility.whenUnlocked.key, String(kSecAttrAccessibleWhenUnlocked))
        XCTAssertEqual(KeychainAccessibility.whenUnlockedThisDeviceOnly.key, String(kSecAttrAccessibleWhenUnlockedThisDeviceOnly))
    }

}
#endif
