//
//  FileStorage+Key.swift
//  KeyValueStorage
//
//  Created by nsahakyan@servicetitan.com on 16.10.26.
//

import Foundation

// MARK: - FileStorage + Key

public extension FileStorage {
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
    enum Protection: Sendable {
        case inherited
        case none
        case complete
        case completeUnlessOpen
        case completeUntilFirstUserAuthentication
    }
}
