//
//  DataStorageTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class DataStorageTests: XCTestCase {
    func testEveryDefaultScopeSharesTheLibrarysNamespace() {
        XCTAssertEqual(MockScope.defaultNamespace, "KeyValueStorage")
        XCTAssertEqual(FileStorage.Scope.default, .own(namespace: "KeyValueStorage"))
        XCTAssertEqual(InMemoryStorage.Scope.default, .own(namespace: "KeyValueStorage"))
    }

    func testTheDefaultSetSavesAValueAndDeletesNil() throws {
        // Given
        let storage = DefaultSetStorage(scope: .init(name: "set"))

        // When
        try storage.set(Data([1]), forKey: "key")
        try storage.set(nil, forKey: "key")

        // Then
        XCTAssertEqual(storage.calls, [.save(Data([1]), "key"), .delete("key")])
    }

    func testTheDefaultSetReportsTheStoragesError() {
        // Given
        let storage = DefaultSetStorage(scope: .init(name: "set"))
        storage.error = MockError(id: 1)

        // When - Then
        assertThrows(MockError(id: 1)) { try storage.set(Data([1]), forKey: "key") }
        assertThrows(MockError(id: 1)) { try storage.set(nil, forKey: "key") }
    }
}

// MARK: - DefaultSetStorage

/// Keeps `DataStorage`'s default `set`, unlike `DataStorageMock`; records every call, and throws `error` instead of answering.
private final class DefaultSetStorage: DataStorage {
    typealias Key = String
    typealias Error = MockError

    let scope: MockScope
    var error: MockError?
    private(set) var calls = [DataStorageCall]()

    init(scope: MockScope) {
        self.scope = scope
    }

    func fetch(forKey key: String) throws(MockError) -> Data? {
        try record(.fetch(key))
        return nil
    }

    func save(_ value: Data, forKey key: String) throws(MockError) {
        try record(.save(value, key))
    }

    func delete(forKey key: String) throws(MockError) {
        try record(.delete(key))
    }

    func clear() throws(MockError) {
        try record(.clear)
    }

    private func record(_ call: DataStorageCall) throws(MockError) {
        calls.append(call)
        if let error {
            throw error
        }
    }
}
