//
//  FixedDirectoriesSQLiteLocator.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation
@testable import KeyValueStorage

/// The default locator with `FixedDirectoriesFileLocator`'s lookups; remove a directory to make its lookup fail.
final class FixedDirectoriesSQLiteLocator: DefaultSQLiteLocator {
    var temporary = URL(fileURLWithPath: "/temporary", isDirectory: true)
    var directories: [FileManager.SearchPathDirectory: URL] = [
        .applicationSupportDirectory: URL(fileURLWithPath: "/support", isDirectory: true),
        .cachesDirectory: URL(fileURLWithPath: "/caches", isDirectory: true)
    ]
    var groupDirectories = ["group.test": URL(fileURLWithPath: "/group", isDirectory: true)]
    var identifier: String? = "com.test.App"

    override var temporaryDirectory: URL {
        temporary
    }

    override func systemDirectory(_ directory: FileManager.SearchPathDirectory) -> URL? {
        directories[directory]
    }

    override func groupDirectory(for groupId: String) -> URL? {
        groupDirectories[groupId]
    }

    override var bundleIdentifier: String? {
        identifier
    }

    override var processName: String {
        "my tool"
    }
}
