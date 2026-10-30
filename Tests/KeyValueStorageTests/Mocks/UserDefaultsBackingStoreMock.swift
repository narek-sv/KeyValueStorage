//
//  UserDefaultsBackingStoreMock.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation
@testable import KeyValueStorage

/// Opens the suites in `suites`; any other name is rejected, as `UserDefaults` rejects some. Records every call.
final class UserDefaultsBackingStoreMock: UserDefaultsBackingStore {
    var suites = [String: UserDefaultsSuiteMock]()
    private(set) var calls = [String]()

    func suite(named name: String) -> (any UserDefaultsSuite)? {
        calls.append(name)
        return suites[name]
    }
}

/// A suite in memory that holds any property-list value, as `UserDefaults` does; records every call.
/// - Note: Its keys compare with Swift's `==`, so keys the real suite tells apart by bytes can share an entry.
final class UserDefaultsSuiteMock: UserDefaultsSuite {
    enum Call: Equatable {
        case read(String)
        case write(Data, String)
        case remove(String)
        case keys
    }

    var values = [String: Any]()
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
}
