//
//  UserDefaultsMock.swift
//
//
//  Created by Narek Sahakyan on 02.03.24.
//

import Foundation
@testable import UnifiedStorage

final class UserDefaultsMock: UserDefaults {
    var storage = [String: Data]()
    override func data(forKey defaultName: String) -> Data? {
        storage[defaultName]
    }
    
    override func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value as? Data
    }
    
    override func removeObject(forKey defaultName: String) {
        storage[defaultName] = nil
    }
    
    override func removePersistentDomain(forName domainName: String) {
        storage.removeAll()
    }
}

