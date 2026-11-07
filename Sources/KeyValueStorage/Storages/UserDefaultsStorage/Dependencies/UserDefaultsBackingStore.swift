//
//  UserDefaultsBackingStore.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import Foundation

// MARK: - UserDefaultsBackingStore

/// One system call per member, without rules: the storage owns them.
public protocol UserDefaultsBackingStore: Sendable {
    /// `UserDefaults(suiteName:)`.
    func suite(named name: String) -> (any UserDefaultsSuite)?
}

// MARK: - UserDefaultsSuite

/// One system call per member, without rules: the storage owns them.
public protocol UserDefaultsSuite: AnyObject, Sendable {
    /// `UserDefaults.object(forKey:)`, which also returns registered defaults.
    func read(forKey key: String) -> Any?
    /// `UserDefaults.set(_:forKey:)`.
    func write(_ data: Data, forKey key: String)
    /// `UserDefaults.removeObject(forKey:)`.
    func remove(forKey key: String)
    /// `UserDefaults.dictionaryRepresentation()`'s keys, the global domain's included, each as stored: keys that differ only
    /// in normalization, such as `"é"` and `"e\u{301}"`, are two.
    func keys() -> [String]
}

// MARK: - DefaultUserDefaultsBackingStoreWrapper

/// The live `UserDefaults`.
/// - Warning: Subclasses inherit `Sendable`: their own state must be thread-safe too.
open class DefaultUserDefaultsBackingStoreWrapper: UserDefaultsBackingStore, @unchecked Sendable {
    public init() { }

    open func suite(named name: String) -> (any UserDefaultsSuite)? {
        UserDefaults(suiteName: name).map(DefaultUserDefaultsSuite.init)
    }
}

// MARK: - DefaultUserDefaultsSuite

/// Unchecked only because `UserDefaults` isn't marked `Sendable` on every SDK; it's thread-safe.
final class DefaultUserDefaultsSuite: UserDefaultsSuite, @unchecked Sendable {
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
        // Through `NSDictionary`: a Swift dictionary merges keys that differ only in normalization, such as `"é"` and `"e\u{301}"`
        (userDefaults.dictionaryRepresentation() as NSDictionary).allKeys.compactMap { $0 as? String }
    }
}
