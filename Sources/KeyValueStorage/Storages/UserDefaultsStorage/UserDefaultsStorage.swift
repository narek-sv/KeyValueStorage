//
//  UserDefaultsStorage.swift
//
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

// MARK: - UserDefaultsStorage

public final class UserDefaultsStorage: KeyValueDataStorage {

    public static var defaultBackingStorage: any UserDefaultsBackingStorage {
        DefaultUserDefaultsBackingStorage()
    }

    // MARK: Properties

    private let suite: any UserDefaultsSuite
    private let keyPrefix: String?
    public let domain: Domain

    // MARK: Initializers

    public init(domain: Domain, backingStorage: any UserDefaultsBackingStorage) throws {
        switch domain {
        case .app(.standard):
            self.suite = backingStorage.standard
            self.keyPrefix = nil
        case let .app(.suite(container)):
            self.suite = try Self.suite(named: backingStorage.appIdentifier + "." + container, in: backingStorage)
            self.keyPrefix = nil
        case let .appGroup(groupId, container):
            self.suite = try Self.suite(named: groupId, in: backingStorage)
            self.keyPrefix = KeyNamespace.prefix(for: container)
        }

        self.domain = domain
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

    public func clear() {
        for key in suite.keys() where keyPrefix.map({ key.hasPrefix($0) }) ?? true {
            suite.remove(forKey: key)
        }
    }

    // MARK: Helpers

    private func storedKey(for key: Key) -> String {
        keyPrefix.map { $0 + key } ?? key
    }

    private static func suite(named name: String, in backingStorage: any UserDefaultsBackingStorage) throws -> any UserDefaultsSuite {
        guard let suite = backingStorage.suite(named: name) else {
            throw Error.failedToInitSharedDefaults
        }

        return suite
    }
}
