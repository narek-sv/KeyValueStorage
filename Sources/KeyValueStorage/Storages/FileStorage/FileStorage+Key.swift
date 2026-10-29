//
//  FileStorage+Key.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - FileStorage + Key

public extension FileStorage {
    /// Any `name`, even an empty one, encoded into a file-safe name.
    /// - Note: `.invalidKey` if the encoded name exceeds 255 bytes, the file system's limit.
    struct Key: KeyValueDataStorageKey {
        public let name: String
        public let protection: Protection

        public init(name: String, protection: Protection = .inherited) {
            self.name = name
            self.protection = protection
        }
    }
}

// MARK: - FileStorage.Key + ExpressibleByStringLiteral

extension FileStorage.Key: ExpressibleByStringLiteral {
    public init(stringLiteral name: String) {
        self.init(name: name)
    }
}

// MARK: - FileStorage.Key + Protection

public extension FileStorage.Key {
    enum Protection: Sendable {
        /// No explicit class: the file gets its folder's class or the app's default.
        case inherited
        case none
        /// Unreadable while the device is locked.
        case complete
        /// Writable while locked; readable only while unlocked.
        case completeUnlessOpen
        /// Readable once the user unlocks the device after a restart.
        case completeUntilFirstUserAuthentication
    }
}
