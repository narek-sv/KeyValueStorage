//
//  UserDefaultsBackingStore.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import Foundation

// MARK: - UserDefaultsBackingStore

public protocol UserDefaultsBackingStore {
    /// `UserDefaults(suiteName:)`.
    func suite(named name: String) -> (any UserDefaultsSuite)?
}

// MARK: - UserDefaultsSuite

public protocol UserDefaultsSuite: AnyObject {
    /// `UserDefaults.object(forKey:)`, which also returns registered defaults.
    func read(forKey key: String) -> Any?
    /// `UserDefaults.set(_:forKey:)`.
    func write(_ data: Data, forKey key: String)
    /// `UserDefaults.removeObject(forKey:)`.
    func remove(forKey key: String)
    /// `UserDefaults.dictionaryRepresentation().keys`, which also lists the global domain's keys.
    func keys() -> [String]
}

// MARK: - DefaultUserDefaultsBackingStoreWrapper

/// The live `UserDefaults`.
open class DefaultUserDefaultsBackingStoreWrapper: UserDefaultsBackingStore {
    public init() { }

    open func suite(named name: String) -> (any UserDefaultsSuite)? {
        UserDefaults(suiteName: name).map(DefaultUserDefaultsSuite.init)
    }
}

// MARK: - DefaultUserDefaultsSuite

final class DefaultUserDefaultsSuite: UserDefaultsSuite {
    private let userDefaults: UserDefaults

    init(_ userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func read(forKey key: String) -> Any? {
        userDefaults.object(forKey: key)
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
