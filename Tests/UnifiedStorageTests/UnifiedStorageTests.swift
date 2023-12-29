//
//  UnifiedStorageTests.swift
//
//
//  Created by Narek Sahakyan on 12.12.23.
//

import XCTest
import Security
@testable import UnifiedStorage

final class UnifiedStorageTests: XCTestCase {
    func testCodes() {
        let key1 = UserDefaultsKey<String>(key: "hello", domain: "aaaa")
        let key2 = UserDefaultsKey<String>(key: "world", domain: "bbbb")
        
        
        
    }
}

extension UnifiedStorageKey {
    static var name: UserDefaultsKey<String> {
        .userDefaults(key: "name")
    }
    
    static var yyy: UserDefaultsKey<XXX> {
        .userDefaults(key: "name")
    }
    
    
    func zzzzz() {
        Task {
//            try await UnifiedStorage().fetch(forKey: .name)
        }
    }
    
    class XXX: Codable, @unchecked Sendable {
        
    }
}

