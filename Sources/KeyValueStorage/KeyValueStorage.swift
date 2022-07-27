//
//  KeyValueStorage.swift
//
//
//  Created by Narek Sahakyan on 7/27/22.
//

import Foundation

final class KeyValueStorage {
    private var inMemoryStorage = [String: Any]()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let userDefaults: UserDefaults
    private let keychain: KeychainHelper
    
    let accessGroup: String?
    
    private static var defaultServiceName: String = {
        Bundle.main.bundleIdentifier ?? "defaultSuiteName"
    }()
    
    init() {
        self.userDefaults = UserDefaults(suiteName: Self.defaultServiceName)!
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
        if case .inMemory = key.storageType {
            inMemoryStorage[key.name] = value
        } else {
            guard let data = try? encoder.encode([key.name: value]) else { return }
            
            switch key.storageType {
            case .userDefaults:
                userDefaults.set(data, forKey: key.name)
            case .keychain:
                keychain.set(data, forKey: key.name)
            case .inMemory:
                break
            }
        }
    }
    
    func fetch<T: Codable>(forKey key: KeyValueStorageKey<T>) -> T? {
        var fetchedData: Data?

        switch key.storageType {
        case .inMemory:
            return inMemoryStorage[key.name] as? T
        case .userDefaults:
            fetchedData = userDefaults.data(forKey: key.name)
        case .keychain:
            fetchedData = keychain.get(forKey: key.name)
        }

        guard let data = fetchedData else { return nil }
        return (try? decoder.decode([String: T].self, from: data))?[key.name]
    }
    
    func delete<T: Codable>(forKey key: KeyValueStorageKey<T>) {
        switch key.storageType {
        case .inMemory:
            inMemoryStorage[key.name] = nil
        case .userDefaults:
            userDefaults.removeObject(forKey: key.name)
        case .keychain:
            keychain.remove(forKey: key.name)
        }
    }
    
    func clear() {
        inMemoryStorage.removeAll()
        userDefaults.removePersistentDomain(forName: accessGroup ?? Self.defaultServiceName)
        keychain.removeAll()
    }
}
