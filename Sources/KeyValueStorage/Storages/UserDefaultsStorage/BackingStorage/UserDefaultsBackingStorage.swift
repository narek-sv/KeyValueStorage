//
//  UserDefaultsBackingStore.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import Foundation

// MARK: - UserDefaultsBackingStore

public protocol UserDefaultsBackingStore {
    var appIdentifier: String { get }

    var standard: any UserDefaultsSuite { get }

    func suite(named name: String) -> (any UserDefaultsSuite)?
}

// MARK: - UserDefaultsSuite

public protocol UserDefaultsSuite: AnyObject {
    func read(forKey key: String) -> Data?
    func write(_ data: Data, forKey key: String)
    func remove(forKey key: String)
    func keys() -> [String]
}

// MARK: - DefaultUserDefaultsBackingStoreWrapper

final class DefaultUserDefaultsBackingStoreWrapper: UserDefaultsBackingStore {
    var appIdentifier: String {
        AppIdentifier.current
    }

    var standard: any UserDefaultsSuite {
        DefaultUserDefaultsSuite(.standard)
    }

    func suite(named name: String) -> (any UserDefaultsSuite)? {
        UserDefaults(suiteName: name).map(DefaultUserDefaultsSuite.init)
    }
}

// MARK: - DefaultUserDefaultsSuite

final class DefaultUserDefaultsSuite: UserDefaultsSuite {
    private let userDefaults: UserDefaults

    init(_ userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func read(forKey key: String) -> Data? {
        userDefaults.data(forKey: key)
    }

    func write(_ data: Data, forKey key: String) {
        userDefaults.set(data, forKey: key)
    }

    func remove(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }

    func keys() -> [String] {
        Array(userDefaults.dictionaryRepresentation().keys)
    }
}
