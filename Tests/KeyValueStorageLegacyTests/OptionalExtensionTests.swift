//
//  OptionalExtensionTests.swift
//  
//
//  Created by Narek Sahakyan on 7/27/22.
//

import XCTest
@testable import KeyValueStorageLegacy

class OptionalExtensionTests: XCTestCase {

    func testSome() {
        // Given
        let int: Int? = 45
        
        // When
        let unwrapped = int.unwrapped(88)
        
        // Then
        XCTAssertEqual(unwrapped, 45)
    }
    
    func testNil() {
        // Given
        let int: Int? = nil
        
        // When
        let unwrapped = int.unwrapped(88)
        
        // Then
        XCTAssertEqual(unwrapped, 88)
    }

}
