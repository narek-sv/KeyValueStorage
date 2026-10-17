//
//  UserDefaultsBackingStorage.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import Foundation

// MARK: - UserDefaultsBackingStorage

/// `UserDefaults` calls of `UserDefaultsStorage`: opens suites.
public protocol UserDefaultsBackingStorage {
    /// The bundle identifier, or the process name for command-line tools.
    var appIdentifier: String { get }

    /// `UserDefaults.standard`.
    var standard: any UserDefaultsSuite { get }

    /// `UserDefaults(suiteName:)`; `nil` for a rejected name.
    func suite(named name: String) -> (any UserDefaultsSuite)?
}

// MARK: - UserDefaultsSuite

/// One defaults suite.
public protocol UserDefaultsSuite: AnyObject {
    /// `UserDefaults.data(forKey:)`.
    func read(forKey key: String) -> Data?

    /// `UserDefaults.set(_:forKey:)`.
    func write(_ data: Data, forKey key: String)

    /// `UserDefaults.removeObject(forKey:)`.
    func remove(forKey key: String)

    /// The keys of `UserDefaults.dictionaryRepresentation()`.
    func keys() -> [String]
}

// MARK: - DefaultUserDefaultsBackingStorage

/// The live `UserDefaultsBackingStorage`.
final class DefaultUserDefaultsBackingStorage: UserDefaultsBackingStorage {
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

/// The live `UserDefaultsSuite`; it wraps `UserDefaults` rather than extend it.
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
