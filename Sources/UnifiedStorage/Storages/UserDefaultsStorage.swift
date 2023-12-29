//
//  UserDefaultsStorage.swift
//  
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

@UserDefaultsActor
open class UserDefaultsStorage: KeyValueDataStorage, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let domain: Domain?
    
    public required nonisolated init(domain: Domain?) throws {
        self.domain = domain
        
        if let domain {
            guard let defaults = UserDefaults(suiteName: domain) else {
                throw Error.failedToInitSharedDefaults
            }
            
            userDefaults = defaults
        } else {
            userDefaults = .standard
        }
    }
    
    public func fetch(forKey key: Key) throws -> Data? {
        userDefaults.data(forKey: key)
    }
    
    public func save(_ value: Data, forKey key: Key) throws {
        userDefaults.set(value, forKey: key)
    }
    
    public func delete(forKey key: Key) throws {
        userDefaults.removeObject(forKey: key)
    }
    
    public func clear() throws {
        userDefaults.removePersistentDomain(forName: domain ?? Self.defaultGroup)
    }
    
}

public extension UserDefaultsStorage {
    typealias Key = String
    typealias Domain = String
    
    enum Error: KeyValueDataStorageError {
        case failedToInitSharedDefaults
        case other(Swift.Error)
    }
}

@globalActor
public final class UserDefaultsActor {
    public actor Actor { }
    public static let shared = Actor()
}

extension UserDefaults: @unchecked Sendable { }

//extension UserDefaultsStorage: KeyValueDataStorage {
//    nonisolated public func fetch(forKey key: Key) throws -> Data? {
//        return nil
//    }
//    
//    nonisolated public func save<Key>(_ value: Data, forKey key: Key) throws {
//
//    }
//}
//
//extension UserDefaultsStorage: KeyValueDataStorageAsync {
//    public func fetch(forKey key: Key, completion: @escaping (Result<Data?, Error>) -> ()) {
//        do {
//            completion(.success(try fetch(forKey: key)))
//        } catch let error as Error  {
//            completion(.failure(error))
//        } catch {
//            completion(.failure(.other(error)))
//        }
//    }
//    
//    public func save<Key>(_ value: Data, forKey key: Key, completion: @escaping (Error?) -> ()) {
//        do {
//            try save(value, forKey: key)
//            completion(nil)
//        } catch let error as Error  {
//            completion(error)
//        } catch {
//            completion(.other(error))
//        }
//    }
//}
//
//extension UserDefaultsStorage: KeyValueDataStorageConcurrent {
//    public func fetchAsync(forKey key: String) async throws -> Data? {
//        try fetch(forKey: key)
//    }
//    
//    public func saveAsync<Key>(_ value: Data, forKey key: Key) async throws {
//        try save(value, forKey: key)
//    }
//}
//
////public class UnifiedStorage {
////    public typealias Key = UnifiedStorageKey
////    private var storages = [AnyHashable?: Any]()
//////    private var storageMaps: [StorageType: any Storage.Type]
//////    init(storageMaps: [StorageType: any Storage.Type] = [
//////        .keychain: KeychainStorage.self,
//////        .userDefaults: UserDefaultsStorage.self
//////    ]) {
//////        self.storageMaps = storageMaps
//////    }
////    
////    private func storage<Storage: KeyValueDataStorage, Value: Codable>(for key: Key<Storage, Value>) throws -> CodingKeyValueStorage<Storage> {
////        if let storage = storages[key.domain], let casted = storage as? CodingKeyValueStorage<Storage> {
////            return casted
////        }
////        
////        let storage = CodingKeyValueStorage(storage: try Storage(domain: key.domain))
////        storages[key.domain] = storage
////        return storage
////    }
////    
////    public func fetch<Storage: KeyValueDataStorage, Value: Codable>(forKey key: Key<Storage, Value>) throws -> Value? {
////        let container = try storage(for: key)
////        return try container.fetch(forKey: CodingKey(key: key.key, codingType: key.codingType))
////    }
////    
////    public func save<Storage: KeyValueDataStorage, Value: Codable>(_ value: Value, forKey key: Key<Storage, Value>) throws {
////        let container = try storage(for: key)
////        return try container.save(value, forKey: CodingKey(key: key.key, codingType: key.codingType))
////    }
////}
////
////typealias UserDefaultsKey<T: Codable> = UnifiedStorageKey<UserDefaultsStorage, T>
////typealias KeychainKey<T: Codable> = UnifiedStorageKey<KeychainStorage, T>
////
////public struct UnifiedStorageKey<Storage: KeyValueDataStorage, Value: Codable> {
////    let key: Storage.Key
////    let domain: Storage.Domain?
////    let codingType: Value.Type
////    
////    public init(key: Storage.Key, domain: Storage.Domain? = nil) {
////        self.key = key
////        self.domain = domain
////        self.codingType = Value.self
////    }
////    
////    static func keychain(key: Storage.Key,
////                         domain: Storage.Domain? = nil)
////    -> UnifiedStorageKey<Storage, Value>
////    where Storage == KeychainStorage {
////        .init(key: key, domain: domain)
////    }
////    
////    static func userDefaults(key: Storage.Key,
////                             domain: Storage.Domain? = nil)
////    -> UnifiedStorageKey<Storage, Value>
////    where Storage == UserDefaultsStorage {
////        .init(key: key, domain: domain)
////    }
////}
////
////extension UnifiedStorageKey {
////    static var accessToken: KeychainKey<String> {
////        .keychain(key: .init(name: "hello", accessibility: .afterFirstUnlock, isSynchronizable: true),
////                  domain: .init(groupID: "groupId", teamID: "teamId"))
////    }
////    
////    static var name: UserDefaultsKey<String> {
////        .userDefaults(key: "name")
////    }
////    
////    static var xxxx: KeychainKey<String> {
////        fatalError()
////    }
////}
////
//////func xxxx() {
//////
//////    let value = UnifiedStorage().fetch(forKey: .)
//////    value
//////}
