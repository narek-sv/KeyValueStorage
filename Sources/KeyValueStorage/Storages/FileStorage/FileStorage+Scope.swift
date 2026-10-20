//
//  FileStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - FileStorage + Scope

public extension FileStorage {
    /// Separates sets of files within a scope; `nil` (the default) stores the files directly in the scope's directory.
    /// - Warning: `clear()` deletes every file in its directory that a key could have written, other code's too; it skips folders and dot files.
    enum Namespace: KeyValueDataStorageNamespace {
        /// The files in the subdirectory with this name.
        case directory(named: String)
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
    
    /// Where the files are stored, which decides who can read them.
    enum Scope: KeyValueDataStorageScope {
        /// In one of the app's base directories.
        case app(AppScope, namespace: Namespace? = nil)
        /// In the App Group's shared container, readable by every app and extension in the group.
        case appGroup(groupId: String, namespace: Namespace? = nil)
        
        public var namespace: Namespace? {
            switch self {
            case let .app(_, namespace):      return namespace
            case let .appGroup(_, namespace): return namespace
            }
        }
        
        public static var `default`: Self {
            .app(.applicationSupport, namespace: .directory(named: Self.defaultName))
        }
    }
}
