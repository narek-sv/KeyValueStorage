//
//  File.swift
//  
//
//  Created by Narek Sahakyan on 02.03.24.
//

import Foundation
@testable import KeyValueStorage

final class InMemoryMock: InMemoryStorage {
    private(set) var saveCalled = false
    private(set) var fetchCalled = false
    private(set) var deleteCalled = false
    private(set) var clearCalled = false

    override func save(_ value: Data, forKey key: InMemoryStorage.Key) {
        saveCalled = true
        super.save(value, forKey: key)
    }
    
    override func fetch(forKey key: InMemoryStorage.Key) -> Data? {
        fetchCalled = true
        return super.fetch(forKey: key)
    }
    
    override func delete(forKey key: InMemoryStorage.Key) {
        deleteCalled = true
        super.delete(forKey: key)
    }
    
    override func clear() {
        clearCalled = true
        super.clear()
    }
}
