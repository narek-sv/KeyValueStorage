//
//  DataStorageMocks.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.10.26.
//

import Foundation
@testable import KeyValueStorage

// MARK: - MockScope

struct MockScope: KeyValueDataStorageScope {
    let name: String

    static var `default`: Self {
        .init(name: "default")
    }
}

// MARK: - MockError

struct MockError: Error, Equatable {
    let id: Int
}

// MARK: - DataStorageCall

enum DataStorageCall: Equatable {
    case fetch(String)
    case save(Data, String)
    case delete(String)
    case clear
}

// MARK: - DataStorageMock

/// A synchronous in-memory storage; records every call, and throws `error` instead of answering.
final class DataStorageMock: KeyValueDataStorage {
    typealias Key = String
    typealias Error = MockError

    let scope: MockScope
    var values = [String: Data]()
    var error: MockError?
    private(set) var calls = [DataStorageCall]()

    init(scope: MockScope) {
        self.scope = scope
    }

    func fetch(forKey key: String) throws(MockError) -> Data? {
        try record(.fetch(key))
        return values[key]
    }

    func save(_ value: Data, forKey key: String) throws(MockError) {
        try record(.save(value, key))
        values[key] = value
    }

    func delete(forKey key: String) throws(MockError) {
        try record(.delete(key))
        values[key] = nil
    }

    func clear() throws(MockError) {
        try record(.clear)
        values = [:]
    }

    private func record(_ call: DataStorageCall) throws(MockError) {
        calls.append(call)
        if let error {
            throw error
        }
    }
}

// MARK: - AsyncDataStorageMock

/// An asynchronous in-memory storage, as an app's server-backed one would be; records every call, and throws `error` instead of answering.
actor AsyncDataStorageMock: AsyncKeyValueDataStorage {
    typealias Key = String
    typealias Error = MockError

    nonisolated let scope: MockScope
    var values = [String: Data]()
    private(set) var error: MockError?
    private(set) var calls = [DataStorageCall]()

    init(scope: MockScope) {
        self.scope = scope
    }

    func fetch(forKey key: String) async throws(MockError) -> Data? {
        try record(.fetch(key))
        return values[key]
    }

    func save(_ value: Data, forKey key: String) async throws(MockError) {
        try record(.save(value, key))
        values[key] = value
    }

    func delete(forKey key: String) async throws(MockError) {
        try record(.delete(key))
        values[key] = nil
    }

    func clear() async throws(MockError) {
        try record(.clear)
        values = [:]
    }

    func fail(with error: MockError?) {
        self.error = error
    }

    func store(_ value: Data, forKey key: String) {
        values[key] = value
    }

    private func record(_ call: DataStorageCall) throws(MockError) {
        calls.append(call)
        if let error {
            throw error
        }
    }
}

// MARK: - DataCoderMock

/// JSON, or `encodeError` and `decodeError` instead.
struct DataCoderMock: DataCoder {
    var encodeError: MockError?
    var decodeError: MockError?

    func encode<Value: CodingValue>(_ value: Value) throws -> Data {
        if let encodeError {
            throw encodeError
        }

        return try JSONDataCoder().encode(value)
    }

    func decode<Value: CodingValue>(_ data: Data) throws -> Value {
        if let decodeError {
            throw decodeError
        }

        return try JSONDataCoder().decode(data)
    }
}
