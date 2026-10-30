//
//  SQLiteLocatorStub.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation
@testable import KeyValueStorage

/// Fixed names, to check that the storage uses exactly what its locator returns; records each call.
final class SQLiteLocatorStub: SQLiteLocator {
    enum Call: Equatable {
        case databaseURL(SQLiteStorage.Scope)
        case storedKey(SQLiteStorage.Key, SQLiteStorage.Scope)
    }

    var databaseURL = URL(fileURLWithPath: "/located/database.sqlite", isDirectory: false)
    var databaseURLError: SQLiteStorage.Error?
    private(set) var calls = [Call]()

    func databaseURL(for scope: SQLiteStorage.Scope) throws(SQLiteStorage.Error) -> URL {
        calls.append(.databaseURL(scope))
        if let databaseURLError {
            throw databaseURLError
        }

        return databaseURL
    }

    func storedKey(forKey key: SQLiteStorage.Key, in scope: SQLiteStorage.Scope) -> String {
        calls.append(.storedKey(key, scope))
        return "located-\(key)"
    }
}
