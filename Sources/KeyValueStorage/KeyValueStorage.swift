//
//  KeyValueStorage.swift
//
//
//  Created by Narek Sahakyan on 7/27/22.
//

import Foundation

final class KeyValueStorage {
    static private  var inMemoryStorage = [String: Any]()
    private var inMemoryStorage = [String: Any]()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let userDefaults: UserDefaults
    private let keychain: KeychainHelper
    
    let accessGroup: String?
    
    private static var defaultServiceName: String = {
        Bundle.main.bundleIdentifier.unwrapped("defaultSuiteName")
    }()
    
    init() {
        self.userDefaults = UserDefaults.standard
        self.keychain = KeychainHelper(serviceName: Self.defaultServiceName)
        self.accessGroup = nil
    }
    
    init(accessGroup: String, teamID: String) {
        self.accessGroup = accessGroup
        self.userDefaults = UserDefaults(suiteName: accessGroup)!
        self.keychain = KeychainHelper(serviceName: Self.defaultServiceName, accessGroup: teamID + "." + accessGroup)
    }

    
    func set<T: Codable>(_ value: T?, forKey key: KeyValueStorageKey<T>) {
        if let value = value {
            save(value, forKey: key)
        } else {
            delete(forKey: key)
        }
    }
    
    func save<T: Codable>(_ value: T, forKey key: KeyValueStorageKey<T>) {
        switch key.storageType {
        case let .inMemory(isStatic):
            if isStatic {
                Self.inMemoryStorage[key.name] = value
            } else {
                inMemoryStorage[key.name] = value
            }
        case .userDefaults:
            guard let data = try? encoder.encode([key.name: value]) else { return }
            userDefaults.set(data, forKey: key.name)
        case let .keychain(accessibility, synchronizable):
            guard let data = try? encoder.encode([key.name: value]) else { return }
            keychain.set(data, forKey: key.name, withAccessibility: accessibility, isSynchronizable: synchronizable)
        }
    }
    
    func fetch<T: Codable>(forKey key: KeyValueStorageKey<T>) -> T? {
        var fetchedData: Data?

        switch key.storageType {
        case let .inMemory(isStatic):
            if isStatic {
                return Self.inMemoryStorage[key.name] as? T
            } else {
                return inMemoryStorage[key.name] as? T
            }
        case .userDefaults:
            fetchedData = userDefaults.data(forKey: key.name)
        case let .keychain(accessibility, synchronizable):
            fetchedData = keychain.get(forKey: key.name, withAccessibility: accessibility, isSynchronizable: synchronizable)
        }

        guard let data = fetchedData else { return nil }
        return (try? decoder.decode([String: T].self, from: data))?[key.name]
    }
    
    func delete<T: Codable>(forKey key: KeyValueStorageKey<T>) {
        switch key.storageType {
        case let .inMemory(isStatic):
            if isStatic {
                Self.inMemoryStorage[key.name] = nil
            } else {
                inMemoryStorage[key.name] = nil
            }
        case .userDefaults:
            userDefaults.removeObject(forKey: key.name)
        case let .keychain(accessibility, synchronizable):
            keychain.remove(forKey: key.name, withAccessibility: accessibility, isSynchronizable: synchronizable)
        }
    }
    
    func clear() {
        inMemoryStorage.removeAll()
        userDefaults.removePersistentDomain(forName: accessGroup ?? Self.defaultServiceName)
        keychain.removeAll()
    }
}
