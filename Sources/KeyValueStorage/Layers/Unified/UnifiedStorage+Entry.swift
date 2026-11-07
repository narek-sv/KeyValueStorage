//
//  UnifiedStorage+Entry.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

// MARK: - UnifiedStorage + Entry

public extension UnifiedStorage {
    /// Where a value lives: its storage type, scope and key, typed by the value. Each storage names its own, such as
    /// `FileStorage.Entry<UUID>`.
    struct Entry<Storage: UnifiedStorable, Value: CodingValue>: Sendable {
        public let key: Storage.Key
        public let scope: Storage.Scope

        public var codingType: Value.Type {
            Value.self
        }

        public var storageType: Storage.Type {
            Storage.self
        }

        public init(key: Storage.Key, scope: Storage.Scope = .default) {
            self.key = key
            self.scope = scope
        }
    }
}

// MARK: - UnifiedStorage.Entry + String

public extension UnifiedStorage.Entry where Storage.Key == ExactString {
    /// Any string as the key, such as one made at runtime, compared by its exact bytes.
    init(key: String, scope: Storage.Scope = .default) {
        self.init(key: ExactString(key), scope: scope)
    }
}

// MARK: - UnifiedStorage.Entry + Hashable

/// Entries of other value or storage types are other types, so `==` compares only the key and scope; the hash also mixes
/// in both types, for dictionaries of `AnyHashable` entries.
extension UnifiedStorage.Entry: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key &&
        lhs.scope == rhs.scope
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(scope)
        hasher.combine(ObjectIdentifier(codingType))
        hasher.combine(ObjectIdentifier(storageType))
    }
}

// MARK: - AsyncDataStorage + Entry

public extension AsyncDataStorage where Self: Sendable {
    /// This storage's `UnifiedStorage.Entry`, such as `FileStorage.Entry<UUID>`: every storage `UnifiedStorage` takes has
    /// one, your own included.
    typealias Entry<Value: CodingValue> = UnifiedStorage.Entry<Self, Value>
}
