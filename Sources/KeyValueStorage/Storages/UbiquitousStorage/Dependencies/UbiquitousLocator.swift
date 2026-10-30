//
//  UbiquitousLocator.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation

// MARK: - UbiquitousLocator

/// A custom locator must:
/// - keep stored keys within 128 UTF-16 code units: the store raises an Objective-C exception, a crash, for longer ones;
/// - make `key(forStoredKey:in:)` the exact inverse of `storedKey(forKey:in:)`, or `clear()` leaves values behind.
@available(watchOS 9.0, *)
public protocol UbiquitousLocator {
    /// `.invalidKey` over 128 UTF-16 code units.
    func storedKey(forKey key: UbiquitousStorage.Key, in scope: UbiquitousStorage.Scope) throws(UbiquitousStorage.Error) -> String

    /// `nil` for stored keys no key of the scope produces.
    func key(forStoredKey storedKey: String, in scope: UbiquitousStorage.Scope) -> UbiquitousStorage.Key?
}

// MARK: - DefaultUbiquitousLocator

/// Stores keys as `<namespace>!/<key>`, with `%` and `/` percent-encoded in the namespace: the `!` marks the library's keys
/// in a store the app's other code also writes to.
/// - Note: A subclass that changes stored keys overrides both key methods.
@available(watchOS 9.0, *)
open class DefaultUbiquitousLocator: UbiquitousLocator {
    private static let maximumKeyLength = 128
    /// Ends the namespace, and marks the library's entries in a store other code also writes to.
    /// The escaped namespace has no `/`, so the first `/` always ends it.
    private static let namespaceMark = "!/"
    /// `/`, which ends the namespace, and `%` so escapes stay unambiguous.
    private static let reservedBytes: Set = [UInt8(ascii: "%"), UInt8(ascii: "/")]

    public init() { }

    open func storedKey(forKey key: UbiquitousStorage.Key, in scope: UbiquitousStorage.Scope) throws(UbiquitousStorage.Error) -> String {
        let storedKey = Self.prefix(for: scope) + key.string
        guard storedKey.utf16.count <= Self.maximumKeyLength else {
            throw .invalidKey(key)
        }

        return storedKey
    }

    open func key(forStoredKey storedKey: String, in scope: UbiquitousStorage.Scope) -> UbiquitousStorage.Key? {
        storedKey.droppingExactPrefix(Self.prefix(for: scope)).map { .init($0) }
    }

    // MARK: Helpers

    private static func prefix(for scope: UbiquitousStorage.Scope) -> String {
        switch scope {
        case let .iCloud(_, namespace):
            return namespace.string.percentEscaping(reservedBytes) + namespaceMark
        }
    }
}
