//
//  KeyValueStorage.swift
//
//
//  Created by Narek Sahakyan on 7/27/22.
//

import Foundation

final class KeyValueStorage {
    static private var inMemoryStorage = [String: [String: Any]]()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let userDefaults: UserDefaults
    private let keychain: KeychainHelper
    private let concurrentQueue = DispatchQueue(label: "KeyValueStorage.default.queue", qos: .userInitiated)
    let accessGroup: String?
    
    private static var defaultServiceName: String = {
        Bundle.main.bundleIdentifier.unwrapped("defaultSuiteName")
    }()
    
    private var serviceName: String {
        accessGroup.unwrapped(Self.defaultServiceName)
    }
    
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
    
    func fetch<T: Codable>(forKey key: KeyValueStorageKey<T>) -> T? {
        concurrentQueue.sync {
            var fetchedData: Data?
            
            switch key.storageType {
            case .inMemory:
                return Self.inMemoryStorage[serviceName]?[key.name] as? T
            case .userDefaults:
                fetchedData = userDefaults.data(forKey: key.name)
            case let .keychain(accessibility, synchronizable):
                fetchedData = keychain.get(forKey: key.name, withAccessibility: accessibility, isSynchronizable: synchronizable)
            }
            
            guard let data = fetchedData else { return nil }
            return (try? decoder.decode([String: T].self, from: data))?[key.name]
        }
    }
    
    func delete<T: Codable>(forKey key: KeyValueStorageKey<T>) {
        concurrentQueue.sync {
            switch key.storageType {
            case .inMemory:
                Self.inMemoryStorage[serviceName]?[key.name] = nil
            case .userDefaults:
                self.userDefaults.removeObject(forKey: key.name)
            case let .keychain(accessibility, synchronizable):
                self.keychain.remove(forKey: key.name, withAccessibility: accessibility, isSynchronizable: synchronizable)
            }
        }
    }
    
    func save<T: Codable>(_ value: T, forKey key: KeyValueStorageKey<T>) {
        concurrentQueue.sync {
            switch key.storageType {
            case .inMemory:
                var data = Self.inMemoryStorage[serviceName].unwrapped([:])
                data[key.name] = value
                Self.inMemoryStorage[serviceName] = data
            case .userDefaults:
                guard let data = try? self.encoder.encode([key.name: value]) else { return }
                self.userDefaults.set(data, forKey: key.name)
            case let .keychain(accessibility, synchronizable):
                guard let data = try? self.encoder.encode([key.name: value]) else { return }
                self.keychain.set(data, forKey: key.name, withAccessibility: accessibility, isSynchronizable: synchronizable)
            }
        }
    }
    
    func clear() {
        concurrentQueue.sync {
            Self.inMemoryStorage.removeAll()
            self.userDefaults.removePersistentDomain(forName: self.accessGroup ?? Self.defaultServiceName)
            self.keychain.removeAll()
        }
    }
}
