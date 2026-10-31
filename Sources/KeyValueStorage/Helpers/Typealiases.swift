//
//  Typealiases.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.12.23.
//

// MARK: - Typealiases

public typealias CodingValue = Codable & Sendable

// The built-in thread-safe variants of the data storages
public typealias IsolatedUserDefaultsStorage = IsolatedKeyValueDataStorage<UserDefaultsStorage>
public typealias IsolatedKeychainStorage = IsolatedKeyValueDataStorage<KeychainStorage>
public typealias IsolatedInMemoryStorage = IsolatedKeyValueDataStorage<InMemoryStorage>
public typealias IsolatedFileStorage = IsolatedKeyValueDataStorage<FileStorage>
public typealias IsolatedSQLiteStorage = IsolatedKeyValueDataStorage<SQLiteStorage>
@available(watchOS 9.0, *)
public typealias IsolatedUbiquitousStorage = IsolatedKeyValueDataStorage<UbiquitousStorage>

// The built-in storages are synchronous and not `Sendable`, so `UnifiedStorage` reaches them through `IsolatedKeyValueDataStorage`
public typealias UserDefaultsKey<Value: CodingValue> = UnifiedStorageKey<IsolatedUserDefaultsStorage, Value>
public typealias KeychainKey<Value: CodingValue> = UnifiedStorageKey<IsolatedKeychainStorage, Value>
public typealias InMemoryKey<Value: CodingValue> = UnifiedStorageKey<IsolatedInMemoryStorage, Value>
public typealias FileKey<Value: CodingValue> = UnifiedStorageKey<IsolatedFileStorage, Value>
public typealias SQLiteKey<Value: CodingValue> = UnifiedStorageKey<IsolatedSQLiteStorage, Value>
@available(watchOS 9.0, *)
public typealias UbiquitousKey<Value: CodingValue> = UnifiedStorageKey<IsolatedUbiquitousStorage, Value>

