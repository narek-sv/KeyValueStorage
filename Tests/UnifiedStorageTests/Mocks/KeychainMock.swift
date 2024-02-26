//
//  KeychainMock.swift
//
//
//  Created by Narek Sahakyan on 26.02.24.
//

import Foundation
@testable import UnifiedStorage

final class KeychainMock: KeychainHelper {
    var getError: Error?
    var setError: KeychainHelperError?
    var removeError: KeychainHelperError?
    var removeAllError: KeychainHelperError?

    override func get(forKey key: String, withAccessibility accessibility: KeychainAccessibility? = nil, isSynchronizable: Bool = false) throws -> Data? {
        if let getError {
            throw getError
        }
        
        return nil
    }
    
    override func set(_ value: Data, forKey key: String, withAccessibility accessibility: KeychainAccessibility? = nil, isSynchronizable: Bool = false) throws {
        if let setError {
            throw setError
        }
    }
    
    override func remove(forKey key: String, withAccessibility accessibility: KeychainAccessibility? = nil, isSynchronizable: Bool = false) throws {
        if let removeError {
            throw removeError
        }
    }
    
    override func removeAll() throws {
        if let removeAllError {
            throw removeAllError
        }
    }
}
