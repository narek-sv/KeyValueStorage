//
//  FileStorage+Scope.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

import Foundation

// MARK: - FileStorage + Scope

public extension FileStorage {
    /// `nil` stores the files directly in the scope's directory.
    /// - Warning: `clear()` deletes every file a key could have written, other code's too; never folders, links,
    ///   or names no key produces, such as `notes.txt`.
    enum Namespace: KeyValueDataStorageNamespace {
        /// Any name, even an empty one, encoded into a file-safe folder name.
        /// - Note: `.invalidNamespace` if the encoded name exceeds 255 bytes, the file system's limit.
        case directory(named: String)
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
        ///   A link isn't followed; resolve it first with `resolvingSymlinksInPath()`.
        case directory(at: URL)
    }
    
    enum Scope: KeyValueDataStorageScope {
        case app(AppScope, namespace: Namespace? = nil)
        /// Readable by every app and extension in the group.
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
