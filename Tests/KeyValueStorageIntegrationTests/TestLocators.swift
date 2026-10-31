//
//  TestLocators.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 30.10.26.
//

import Foundation
import KeyValueStorage

/// The default locator with its system directories and App Group containers in the test's folder, and the bundle ID `app`.
/// Unchecked: used from one test at a time.
final class TestFileLocator: DefaultFileLocator, @unchecked Sendable {
    private let base: URL

    init(base: URL) {
        self.base = base
    }

    override var temporaryDirectory: URL {
        base.appendingPathComponent("tmp", isDirectory: true)
    }

    override func systemDirectory(_ directory: FileManager.SearchPathDirectory) -> URL? {
        [.applicationSupportDirectory: "support", .cachesDirectory: "caches"][directory].map { base.appendingPathComponent($0, isDirectory: true) }
    }

    override func groupDirectory(for groupId: String) -> URL? {
        base.appendingPathComponent(groupId, isDirectory: true)
    }

    override var ownIdentifier: String {
        "app"
    }
}

/// `TestFileLocator`'s places for SQLite, so a scope's database is in the file storage's folder for the same scope.
/// Unchecked: used from one test at a time.
final class TestSQLiteLocator: DefaultSQLiteLocator, @unchecked Sendable {
    private let base: URL

    init(base: URL) {
        self.base = base
    }

    override var temporaryDirectory: URL {
        base.appendingPathComponent("tmp", isDirectory: true)
    }

    override func systemDirectory(_ directory: FileManager.SearchPathDirectory) -> URL? {
        [.applicationSupportDirectory: "support", .cachesDirectory: "caches"][directory].map { base.appendingPathComponent($0, isDirectory: true) }
    }

    override func groupDirectory(for groupId: String) -> URL? {
        base.appendingPathComponent(groupId, isDirectory: true)
    }

    override var ownIdentifier: String {
        "app"
    }
}

/// The default locator with a bundle ID of the test's choice, so its own suite is the test's alone.
/// Unchecked: used from one test at a time.
final class TestUserDefaultsLocator: DefaultUserDefaultsLocator, @unchecked Sendable {
    private let identifier: String

    init(bundleIdentifier: String) {
        identifier = bundleIdentifier
    }

    override var ownIdentifier: String {
        identifier
    }
}
