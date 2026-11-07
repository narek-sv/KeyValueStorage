//
//  CodingStorageTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

/// Synchronous test methods: a synchronous storage keeps the coding layer free of `await`.
final class CodingStorageTests: XCTestCase {
    private typealias Error = CodingStorageError<DataStorageMock>

    private let storage = DataStorageMock(scope: .init(name: "scope"))
    private let key = CodingStorageKey<DataStorageMock, Int>(key: "key")
    private let error = MockError(id: 1)

    // MARK: Fetch

    func testFetchWithoutAValueIsNil() throws {
        XCTAssertNil(try makeStorage().fetch(forKey: key))
        XCTAssertEqual(storage.calls, [.fetch("key")])
    }

    func testFetchDecodesTheStoredData() throws {
        // Given
        storage.values["key"] = Data("42".utf8)

        // When - Then
        XCTAssertEqual(try makeStorage().fetch(forKey: key), 42)
    }

    func testFetchReportsTheStoragesFailure() {
        // Given
        storage.error = error

        // When - Then
        assertThrows(Error.storage(error)) { try makeStorage().fetch(forKey: key) }
    }

    func testFetchReportsTheCodersFailure() {
        // Given
        storage.values["key"] = Data("42".utf8)

        // When - Then
        assertThrows(Error.coding(error)) { try makeStorage(coder: DataCoderMock(decodeError: error)).fetch(forKey: key) }
    }

    // MARK: Save

    func testSaveWritesTheEncodedValue() throws {
        // When
        try makeStorage().save(42, forKey: key)

        // Then
        XCTAssertEqual(storage.calls, [.save(Data("42".utf8), "key")])
    }

    func testSaveReportsTheCodersFailureWithoutWriting() {
        assertThrows(Error.coding(error)) { try makeStorage(coder: DataCoderMock(encodeError: error)).save(42, forKey: key) }
        XCTAssertEqual(storage.calls, [])
    }

    func testSaveReportsTheStoragesFailure() {
        // Given
        storage.error = error

        // When - Then
        assertThrows(Error.storage(error)) { try makeStorage().save(42, forKey: key) }
    }

    // MARK: Set, Delete and Clear

    func testSetPassesTheEncodedValueOrNilToTheStoragesSet() throws {
        // Given
        let storage = makeStorage()

        // When
        try storage.set(42, forKey: key)
        try storage.set(nil, forKey: key)

        // Then
        XCTAssertEqual(self.storage.calls, [.set(Data("42".utf8), "key"), .set(nil, "key")])
    }

    func testSetReportsTheCodersFailureWithoutWriting() {
        assertThrows(Error.coding(error)) { try makeStorage(coder: DataCoderMock(encodeError: error)).set(42, forKey: key) }
        XCTAssertEqual(storage.calls, [])
    }

    func testSetReportsTheStoragesFailure() {
        // Given
        storage.error = error

        // When - Then
        assertThrows(Error.storage(error)) { try makeStorage().set(42, forKey: key) }
        assertThrows(Error.storage(error)) { try makeStorage().set(nil, forKey: key) }
    }

    func testDeleteAndClearReachTheStorage() throws {
        // Given
        let storage = makeStorage()

        // When
        try storage.delete(forKey: key)
        try storage.clear()

        // Then
        XCTAssertEqual(self.storage.calls, [.delete("key"), .clear])
    }

    func testDeleteAndClearReportTheStoragesFailure() {
        // Given
        storage.error = error

        // When - Then
        assertThrows(Error.storage(error)) { try makeStorage().delete(forKey: key) }
        assertThrows(Error.storage(error)) { try makeStorage().clear() }
    }

    // MARK: Scope

    func testScopeIsTheStorages() {
        XCTAssertEqual(makeStorage().scope, storage.scope)
    }

    // MARK: Helpers

    private func makeStorage(coder: any DataCoder = DataCoderMock()) -> CodingStorage<DataStorageMock> {
        CodingStorage(storage: storage, coder: coder)
    }
}
