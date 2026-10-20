//
//  UserDefaultsStorage.swift
//
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - UserDefaultsStorage

public final class UserDefaultsStorage: KeyValueDataStorage {

    // MARK: Properties

    private let suite: any UserDefaultsSuite
    private let keyPrefix: String?
    public let scope: Scope

    // MARK: Initializers

    public init(scope: Scope, backingStorage: any UserDefaultsBackingStore) throws {
        switch scope {
        case .app(.standard, _):
            self.suite = backingStorage.standard
        case let .app(.suite(name), _):
            self.suite = try Self.suite(named: name, in: backingStorage)
        case let .appGroup(groupId, _):
            self.suite = try Self.suite(named: groupId, in: backingStorage)
        }

        switch scope.namespace {
        case let .keyPrefix(name)?:
            self.keyPrefix = KeyNamespace.prefix(for: name)
        case nil:
            self.keyPrefix = nil
        }

        self.scope = scope
    }

    public convenience init(scope: Scope) throws {
        try self.init(scope: scope, backingStorage: DefaultUserDefaultsBackingStoreWrapper())
    }

    // MARK: Main Functionality

    public func fetch(forKey key: Key) -> Data? {
        suite.read(forKey: storedKey(for: key))
    }

    public func save(_ value: Data, forKey key: Key) {
        suite.write(value, forKey: storedKey(for: key))
    }

    public func delete(forKey key: Key) {
        suite.remove(forKey: storedKey(for: key))
    }

    public func set(_ value: Data?, forKey key: Key) {
        if let value {
            save(value, forKey: key)
        } else {
            delete(forKey: key)
        }
    }

    public func clear() {
        for key in suite.keys() where keyPrefix.map({ key.hasPrefix($0) }) ?? true {
            suite.remove(forKey: key)
        }
    }

    // MARK: Helpers

    private func storedKey(for key: Key) -> String {
        keyPrefix.map { $0 + key } ?? key
    }

    private static func suite(named name: String, in backingStorage: any UserDefaultsBackingStore) throws -> any UserDefaultsSuite {
        guard let suite = backingStorage.suite(named: name) else {
            throw Error.invalidSuiteName(name)
        }

        return suite
    }
}
