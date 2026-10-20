//
//  SQLiteStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - SQLiteStorage + Scope

public extension SQLiteStorage {
    /// Separates databases within a scope; `nil` (the default) stores `KeyValueStorage.sqlite` directly in the scope's directory.
    enum Namespace: KeyValueDataStorageNamespace {
        /// A separate database in the subdirectory with this name.
        case directory(named: String)
    }
    
    /// The data protection class of the database and its `-wal` and `-shm` files.
    enum Protection: Sendable {
        /// No explicit class (the default), so the files get their directory's class or the app's default protection.
        case inherited
        /// Readable at any time.
        case none
        /// Unreadable while the device is locked, even by an open database.
        case complete
        /// Unreadable while the device is locked, unless the database was already open.
        case completeUnlessOpen
        /// Readable once the user unlocks the device after a restart.
        case completeUntilFirstUserAuthentication
    }
    
    /// The base directory of an app scope: a standard one, or any directory.
    /// - Warning: On macOS without App Sandbox, the standard directories are shared by all of the user's apps.
    enum AppScope: Hashable, Sendable {
        /// Application Support, which is backed up and never emptied by the system.
        case applicationSupport
        /// Caches, which isn't backed up and which the system can empty when storage runs low.
        case cache
        /// Documents, which is backed up and can be visible to the user.
        case documents
        /// The temporary directory, which the system can empty when the app isn't running.
        case temporary
        /// Any directory, such as a folder the user picked or a temporary folder in tests.
        /// - Warning: Scopes compare URLs as given, so `/a/b`, `/a/b/` and a symlinked path are separate storages.
        case directory(at: URL)
    }
    
    /// Where the database is stored, which decides who can read it, and its file protection.
    enum Scope: KeyValueDataStorageScope {
        /// In one of the app's base directories.
        case app(AppScope, namespace: Namespace? = nil, protection: Protection = .inherited)
        /// In the App Group's shared container, readable by every app and extension in the group.
        case appGroup(groupId: String, namespace: Namespace? = nil, protection: Protection = .inherited)
        
        public var namespace: Namespace? {
            switch self {
            case let .app(_, namespace, _):         return namespace
            case let .appGroup(_, namespace, _):    return namespace
            }
        }
        
        public static var `default`: Self {
            .app(.applicationSupport, namespace: .directory(named: Self.defaultNamespace))
        }
    }
}
