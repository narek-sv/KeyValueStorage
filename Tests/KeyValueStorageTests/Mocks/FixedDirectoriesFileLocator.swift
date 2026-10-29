//
//  FixedDirectoriesFileLocator.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 28.10.26.
//

import Foundation
@testable import KeyValueStorage

/// The default locator with system directories at fixed paths; remove one to make its lookup fail.
final class FixedDirectoriesFileLocator: DefaultFileLocator {
    var temporary = URL(fileURLWithPath: "/temporary", isDirectory: true)
    var directories: [FileManager.SearchPathDirectory: URL] = [
        .applicationSupportDirectory: URL(fileURLWithPath: "/support", isDirectory: true),
        .cachesDirectory: URL(fileURLWithPath: "/caches", isDirectory: true),
        .documentDirectory: URL(fileURLWithPath: "/documents", isDirectory: true)
    ]
    var groupDirectories = ["group.test": URL(fileURLWithPath: "/group", isDirectory: true)]

    override var temporaryDirectory: URL {
        temporary
    }

    override func systemDirectory(_ directory: FileManager.SearchPathDirectory) -> URL? {
        directories[directory]
    }

    override func groupDirectory(for groupId: String) -> URL? {
        groupDirectories[groupId]
    }
}
