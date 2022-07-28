//
//  KeychainHelperTests.swift
//  
//
//  Created by Narek Sahakyan on 7/28/22.
//

import XCTest
@testable import KeyValueStorage

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
        XCTAssertNil(helper.get(forKey: key, withAccessibility: .always))
        XCTAssertNil(helper.get(forKey: key, isSynchronizable: true))

        // When
        XCTAssertTrue(helper.set(data, forKey: key))
        
        // Then
        XCTAssertEqual(helper.get(forKey: key), data)
        XCTAssertEqual(helper.get(forKey: key, withAccessibility: .always), data)
        XCTAssertNil(helper.get(forKey: key, isSynchronizable: true))
        
        // When
        XCTAssertTrue(helper.set(newData, forKey: key))

        // Then
        XCTAssertEqual(helper.get(forKey: key), newData)
        XCTAssertEqual(helper.get(forKey: key, withAccessibility: .always), newData)
        XCTAssertNil(helper.get(forKey: key, isSynchronizable: true))
        
        // When
        XCTAssertTrue(helper.remove(forKey: key))
        
        // Then
        XCTAssertNil(helper.get(forKey: key))
        XCTAssertNil(helper.get(forKey: key, withAccessibility: .always))
        XCTAssertNil(helper.get(forKey: key, isSynchronizable: true))
        
        // When
        XCTAssertFalse(helper.set(data, forKey: key, isSynchronizable: true))
        
        // Then
        XCTAssertNil(helper.get(forKey: key))
        XCTAssertNil(helper.get(forKey: key, withAccessibility: .always))
        XCTAssertNil(helper.get(forKey: key, withAccessibility: .afterFirstUnlock))
        XCTAssertNil(helper.get(forKey: key, isSynchronizable: true))
    }
    
    func testAccessibilityRawValues() {
        // Given
        XCTAssertEqual(KeychainAccessibility.afterFirstUnlock.key, String(kSecAttrAccessibleAfterFirstUnlock))
        XCTAssertEqual(KeychainAccessibility.afterFirstUnlockThisDeviceOnly.key, String(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly))
        XCTAssertEqual(KeychainAccessibility.always.key, String(kSecAttrAccessibleAlways))
        XCTAssertEqual(KeychainAccessibility.whenPasscodeSetThisDeviceOnly.key, String(kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly))
        XCTAssertEqual(KeychainAccessibility.alwaysThisDeviceOnly.key, String(kSecAttrAccessibleAlwaysThisDeviceOnly))
        XCTAssertEqual(KeychainAccessibility.whenUnlocked.key, String(kSecAttrAccessibleWhenUnlocked))
        XCTAssertEqual(KeychainAccessibility.whenUnlockedThisDeviceOnly.key, String(kSecAttrAccessibleWhenUnlockedThisDeviceOnly))
    }

}
#endif
