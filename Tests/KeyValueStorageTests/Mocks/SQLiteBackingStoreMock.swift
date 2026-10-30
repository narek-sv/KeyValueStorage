//
//  SQLiteBackingStoreMock.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation
@testable import KeyValueStorage

/// Records every call, and throws the error set for a call instead of answering it.
final class SQLiteBackingStoreMock: SQLiteBackingStore {
    enum Call: Equatable {
        case createDirectory(URL)
        case open(URL, FileProtectionType?)
    }

    let database = SQLiteDatabaseMock()
    var createDirectoryError: (any Error)?
    var openError: SQLiteError?
    private(set) var calls = [Call]()

    func createDirectory(at url: URL) throws {
        calls.append(.createDirectory(url))
        if let createDirectoryError {
            throw createDirectoryError
        }
    }

    func open(at url: URL, protection: FileProtectionType?) throws(SQLiteError) -> any SQLiteDatabase {
        calls.append(.open(url, protection))
        if let openError {
            throw openError
        }

        return database
    }
}

/// An in-memory table; records every call, and throws `error` instead of answering.
final class SQLiteDatabaseMock: SQLiteDatabase {
    enum Call: Equatable {
        case read(String)
        case write(Data, String)
        case remove(String)
        case removeAll
    }

    var values = [String: Data]()
    var error: SQLiteError?
    private(set) var calls = [Call]()

    func read(forKey key: String) throws(SQLiteError) -> Data? {
        try record(.read(key))
        return values[key]
    }

    func write(_ data: Data, forKey key: String) throws(SQLiteError) {
        try record(.write(data, key))
        values[key] = data
    }

    func remove(forKey key: String) throws(SQLiteError) {
        try record(.remove(key))
        values[key] = nil
    }

    func removeAll() throws(SQLiteError) {
        try record(.removeAll)
        values = [:]
    }

    private func record(_ call: Call) throws(SQLiteError) {
        calls.append(call)
        if let error {
            throw error
        }
    }
}
