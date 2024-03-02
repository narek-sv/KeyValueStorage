//
//  Typealiases.swift
//  
//
//  Created by Narek Sahakyan on 29.12.23.
//

import Foundation

public typealias CodingValue = Codable & Sendable
public typealias UserDefaultsKey<Value: CodingValue> = UnifiedStorageKey<UserDefaultsStorage, Value>
public typealias KeychainKey<Value: CodingValue> = UnifiedStorageKey<KeychainStorage, Value>
public typealias InMemoryKey<Value: CodingValue> = UnifiedStorageKey<InMemoryStorage, Value>
public typealias FileKey<Value: CodingValue> = UnifiedStorageKey<FileStorage, Value>

