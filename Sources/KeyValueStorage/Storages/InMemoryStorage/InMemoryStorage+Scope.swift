//
//  InMemoryStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - InMemoryStorage + Scope

public extension InMemoryStorage {
    /// Any string, even an empty one.
    typealias Namespace = ExactString

    /// Values live until the process exits.
    enum Scope: KeyValueDataStorageScope {
        /// This process's own memory.
        case own(namespace: Namespace)

        public static var `default`: Self {
            .own(namespace: defaultNamespace)
        }
    }
}
