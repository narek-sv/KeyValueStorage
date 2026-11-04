//
//  Factory.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

// MARK: - Factory

public extension UnifiedStorage {
    /// Makes each storage type and scope's storages, in steps: creates the storage with its `init(scope:)`, picks
    /// `RawDataCoder`, wraps both in an `AsyncCodingStorage`, and doesn't observe it. Start from `default` and add a
    /// modifier for each change, for every storage type or for one.
    ///
    /// The last modifier decides: each gets what the ones before it make, and returns it as is, changed or replaced, so add
    /// the modifiers for every storage type first. A modifier for one type changes only that exact type:
    /// `IsolatedDataStorage<FileStorage>`, which has `FileStorage`'s scopes, isn't `FileStorage`.
    struct Factory: Sendable {
        var modifiers = [any Modifier]()

        /// No modifiers: every step's default.
        public static var `default`: Self {
            Self()
        }

        /// Adds a modifier of your own, after the others, so it decides over them.
        public func modifier(_ modifier: some Modifier) -> Self {
            var factory = self
            factory.modifiers.append(modifier)
            return factory
        }
    }
}

