//
//  UbiquitousBackingStoreMock.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation
@testable import KeyValueStorage

/// A store in memory that holds any property-list value, as the iCloud key-value store does; records every call.
/// - Note: Its keys compare with Swift's `==`, so keys the real store tells apart by bytes can share an entry.
final class UbiquitousBackingStoreMock: UbiquitousBackingStore {
    enum Call: Equatable {
        case read(String)
        case write(Data, String)
        case remove(String)
        case keys
        case synchronize
    }

    var values = [String: Any]()
    var synchronizes = true
    private(set) var calls = [Call]()

    func read(forKey key: String) -> Any? {
        calls.append(.read(key))
        return values[key]
    }

    func write(_ data: Data, forKey key: String) {
        calls.append(.write(data, key))
        values[key] = data
    }

    func remove(forKey key: String) {
        calls.append(.remove(key))
        values[key] = nil
    }

    func keys() -> [String] {
        calls.append(.keys)
        return values.keys.sorted()
    }

    func synchronize() -> Bool {
        calls.append(.synchronize)
        return synchronizes
    }
}
