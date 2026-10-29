//
//  SQLiteStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - SQLiteStorage + Scope

public extension SQLiteStorage {
    /// `nil` keeps the hidden `.KeyValueStorage.sqlite` directly in the scope's directory.
    enum Namespace: KeyValueDataStorageNamespace {
        /// Any name, even an empty one, encoded into a file-safe folder name.
        /// - Note: `.invalidNamespace` if the encoded name exceeds 255 bytes, the file system's limit.
        case directory(named: String)
    }
    
    /// Applies to the database and its `-wal` and `-shm` files.
    enum Protection: Sendable {
        /// No explicit class: the files get their folder's class or the app's default.
        case inherited
        case none
        /// Unreadable while locked, even by an open database.
        case complete
        /// Unreadable while locked, unless the database was already open.
        case completeUnlessOpen
        /// Readable once the user unlocks the device after a restart.
        case completeUntilFirstUserAuthentication
    }
    
    /// - Warning: On macOS without App Sandbox, the standard directories are shared by all of the user's apps.
    enum AppScope: Hashable, Sendable {
        /// Backed up; never emptied by the system.
        case applicationSupport
        /// Not backed up; the system can empty it when storage runs low.
        case cache
        /// Backed up; can be visible to the user.
        case documents
        /// The system can empty it when the app isn't running.
        case temporary
        /// - Warning: URLs compare as given: `/a/b`, `/a/b/` and a symlinked path are separate scopes.
        case directory(at: URL)
    }
    
    enum Scope: KeyValueDataStorageScope {
        case app(AppScope, namespace: Namespace? = nil, protection: Protection = .inherited)
        /// Readable by every app and extension in the group.
        case appGroup(groupId: String, namespace: Namespace? = nil, protection: Protection = .inherited)
        
        public var namespace: Namespace? {
            switch self {
            case let .app(_, namespace, _):         return namespace
            case let .appGroup(_, namespace, _):    return namespace
            }
        }
        
        public static var `default`: Self {
            .app(.applicationSupport, namespace: .directory(named: Self.defaultName))
        }
    }
}
