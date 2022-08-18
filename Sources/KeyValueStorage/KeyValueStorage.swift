//
//  KeyValueStorage.swift
//
//
//  Created by Narek Sahakyan on 7/27/22.
//

import Foundation

/// The main class responsible for manipulating the storage.
final class KeyValueStorage {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let userDefaults: UserDefaults
    private let keychain: KeychainHelper
    private let concurrentQueue = DispatchQueue(label: "KeyValueStorage.default.queue", qos: .userInitiated)
    private var serviceName: String { accessGroup.unwrapped(Self.defaultServiceName) }
    private static var defaultServiceName: String = { Bundle.main.bundleIdentifier.unwrapped("defaultSuiteName") }()
    private static var inMemoryStorage = [String: [String: Any]]()
    
    /// `accessGroup` is used to identify which  Access Group all items belongs to. This allows using shared access between different applications.
    let accessGroup: String?
    
    /// Default initializer, which doesn't allow using shared access between different applications.
    init() {
        self.userDefaults = UserDefaults.standard
        self.keychain = KeychainHelper(serviceName: Self.defaultServiceName)
        self.accessGroup = nil
    }
    
    /// This initializer allows using shared access between different applications if appropriately configured.
    ///
    /// - parameter accessGroup: The access group name. Make sure to add appropriate capabilities in your app and register the name before using it.
    /// - parameter teamID: The Team ID of your development team. It can be found on developer.apple.com.
    init(accessGroup: String, teamID: String) {
        self.accessGroup = accessGroup
        self.userDefaults = UserDefaults(suiteName: accessGroup)!
        self.keychain = KeychainHelper(serviceName: Self.defaultServiceName, accessGroup: teamID + "." + accessGroup)
    }
    
    /// Sets the item identified by the key to the provided value.
    ///
    /// - parameter value: The item to be saved or deleted if nil is provided.
    /// - parameter forKey: The key to uniquely identify the item.
    func set<T: Codable>(_ value: T?, forKey key: KeyValueStorageKey<T>) {
        if let value = value {
            save(value, forKey: key)
        } else {
            delete(forKey: key)
        }
    }
    
    /// Fetches the item associated with the key.
    ///
    /// - parameter key: The key to uniquely identify the item.
    /// - returns: The item or nil if there is no item associated with the specified key.
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
    
    /// Deletes the item associated with the key or does nothing if there is no such item.
    ///
    /// - parameter value: The item to be saved.
    /// - parameter key: The key to uniquely identify the item.
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
    
    /// Saves the item and associates it with the key or overrides the value if there is already such item.
    ///
    /// - parameter value: The item to be saved.
    /// - parameter key: The key to uniquely identify the item.
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
    
    /// Clears all the items in all storage types.
    func clear() {
        concurrentQueue.sync {
            Self.inMemoryStorage.removeAll()
            self.userDefaults.removePersistentDomain(forName: self.accessGroup ?? Self.defaultServiceName)
            self.keychain.removeAll()
        }
    }
}
