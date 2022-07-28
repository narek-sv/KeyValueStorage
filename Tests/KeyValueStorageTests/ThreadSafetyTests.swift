//
//  ThreadSafetyTests.swift
//  
//
//  Created by Narek Sahakyan on 7/28/22.
//

import XCTest
@testable import KeyValueStorage

class ThreadSafetyTests: XCTestCase {
    private var storage: KeyValueStorage!
    
    override func setUp() {
        storage = KeyValueStorage()
    }
    
    override func tearDown() {
        storage.clear()
    }

    func testSafety() throws {
        stressTest(in: .inMemory(isStatic: false))
        stressTest(in: .inMemory(isStatic: true))
        stressTest(in: .userDefaults)
        stressTest(in: .keychain())
    }
        
    private func stressTest(in storage: KeyValueStorageType, timeout: TimeInterval = 100) {
        let group = DispatchGroup()
        let keyNames = (0...1000).map { _ in UUID().uuidString }
        let keys = keyNames.map { KeyValueStorageKey<String>(name: $0, storage: storage) }
        let promise = expectation(description: "wait for threads")
        
        for key in keys {
            group.enter()

            DispatchQueue.global().async {
                switch (0...90).randomElement()! {
                case 0...20:
                    _ = self.storage.fetch(forKey: key)
                case 21...40:
                    self.storage.set("xxx", forKey: key)
                case 41...60:
                    self.storage.delete(forKey: key)
                case 61...80:
                    self.storage.set("xxx", forKey: key)
                default:
                    self.storage.clear()
                }
                
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            promise.fulfill()
        }
        
        wait(for: [promise], timeout: timeout)
    }

}
