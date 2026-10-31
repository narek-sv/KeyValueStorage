//
//  UnifiedStorage+Key.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

// MARK: - UnifiedStorageKey

public struct UnifiedStorageKey<Storage: UnifiedStorable, Value: CodingValue>: Sendable {
    public let key: Storage.Key
    public let scope: Storage.Scope
    public let codingType: Value.Type
    public let storageType: Storage.Type
    
    public init(key: Storage.Key, scope: Storage.Scope = .default) {
        self.key = key
        self.scope = scope
        self.codingType = Value.self
        self.storageType = Storage.self
    }
}

// MARK: - UnifiedStorageKey + Hashable

extension UnifiedStorageKey: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key &&
        lhs.scope == rhs.scope &&
        lhs.codingType == rhs.codingType &&
        lhs.storageType == rhs.storageType
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(scope)
        hasher.combine(ObjectIdentifier(codingType))
        hasher.combine(ObjectIdentifier(storageType))
    }
}
