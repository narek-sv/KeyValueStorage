//
//  FileStorage+Key.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - FileStorage + Key

public extension FileStorage {
    /// A value in its own file, named `name` with `%` and characters that change with case percent-encoded.
    struct Key: KeyValueDataStorageKey {
        public let name: String
        public let protection: Protection

        public init(name: String, protection: Protection = .inherited) {
            self.name = name
            self.protection = protection
        }
    }
}

// MARK: - FileStorage.Key + Protection

public extension FileStorage.Key {
    /// The data protection class of the key's file.
    enum Protection: Sendable {
        /// No explicit class (the default), so the file gets its directory's class or the app's default protection.
        case inherited
        /// Readable at any time.
        case none
        /// Unreadable while the device is locked.
        case complete
        /// Writable while the device is locked, but readable only while it's unlocked.
        case completeUnlessOpen
        /// Readable once the user unlocks the device after a restart.
        case completeUntilFirstUserAuthentication
    }
}
