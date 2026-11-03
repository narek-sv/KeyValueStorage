//
//  AsyncCodingStorageTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class AsyncCodingStorageTests: XCTestCase {
    private typealias Error = CodingStorageError<AsyncDataStorageMock>

    private let storage = AsyncDataStorageMock(scope: .init(name: "scope"))
    private let key = CodingStorageKey<AsyncDataStorageMock, Int>(key: "key")
    private let error = MockError(id: 1)

    // MARK: Fetch

    func testFetchWithoutAValueIsNil() async throws {
        let value = try await makeStorage().fetch(forKey: key)
        XCTAssertNil(value)
        let calls = await storage.calls
        XCTAssertEqual(calls, [.fetch("key")])
    }

    func testFetchDecodesTheStoredData() async throws {
        // Given
        await storage.store(Data("42".utf8), forKey: "key")

        // When
        let value = try await makeStorage().fetch(forKey: key)

        // Then
        XCTAssertEqual(value, 42)
    }

    func testFetchReportsTheStoragesFailure() async {
        // Given
        await storage.fail(with: error)

        // When - Then
        await assertThrows(Error.storage(error)) { try await makeStorage().fetch(forKey: key) }
    }

    func testFetchReportsTheCodersFailure() async {
        // Given
        await storage.store(Data("42".utf8), forKey: "key")

        // When - Then
        await assertThrows(Error.coding(error)) { try await makeStorage(coder: DataCoderMock(decodeError: error)).fetch(forKey: key) }
    }

    // MARK: Save

    func testSaveWritesTheEncodedValue() async throws {
        // When
        try await makeStorage().save(42, forKey: key)

        // Then
        let calls = await storage.calls
        XCTAssertEqual(calls, [.save(Data("42".utf8), "key")])
    }

    func testSaveReportsTheCodersFailureWithoutWriting() async {
        await assertThrows(Error.coding(error)) { try await makeStorage(coder: DataCoderMock(encodeError: error)).save(42, forKey: key) }
        let calls = await storage.calls
        XCTAssertEqual(calls, [])
    }

    func testSaveReportsTheStoragesFailure() async {
        // Given
        await storage.fail(with: error)

        // When - Then
        await assertThrows(Error.storage(error)) { try await makeStorage().save(42, forKey: key) }
    }

    // MARK: Set, Delete and Clear

    func testSetPassesTheEncodedValueOrNilToTheStoragesSet() async throws {
        // Given
        let coding = makeStorage()

        // When
        try await coding.set(42, forKey: key)
        try await coding.set(nil, forKey: key)

        // Then
        let calls = await storage.calls
        XCTAssertEqual(calls, [.set(Data("42".utf8), "key"), .set(nil, "key")])
    }

    func testSetReportsTheCodersFailureWithoutWriting() async {
        await assertThrows(Error.coding(error)) { try await makeStorage(coder: DataCoderMock(encodeError: error)).set(42, forKey: key) }
        let calls = await storage.calls
        XCTAssertEqual(calls, [])
    }

    func testSetReportsTheStoragesFailure() async {
        // Given
        await storage.fail(with: error)

        // When - Then
        await assertThrows(Error.storage(error)) { try await makeStorage().set(42, forKey: key) }
        await assertThrows(Error.storage(error)) { try await makeStorage().set(nil, forKey: key) }
    }

    func testDeleteAndClearReachTheStorage() async throws {
        // Given
        let coding = makeStorage()

        // When
        try await coding.delete(forKey: key)
        try await coding.clear()

        // Then
        let calls = await storage.calls
        XCTAssertEqual(calls, [.delete("key"), .clear])
    }

    func testDeleteAndClearReportTheStoragesFailure() async {
        // Given
        await storage.fail(with: error)

        // When - Then
        await assertThrows(Error.storage(error)) { try await makeStorage().delete(forKey: key) }
        await assertThrows(Error.storage(error)) { try await makeStorage().clear() }
    }

    // MARK: Synchronous Storages

    func testASynchronousStorageWorksOnTheAsyncPath() async throws {
        // Given
        let storage = DataStorageMock(scope: .init(name: "sync"))
        let coding = AsyncCodingStorage(storage: storage, coder: DataCoderMock())
        let key = CodingStorageKey<DataStorageMock, Int>(key: "key")

        // When
        try await coding.save(42, forKey: key)
        let value = try await coding.fetch(forKey: key)
        try await coding.clear()

        // Then
        XCTAssertEqual(value, 42)
        XCTAssertEqual(storage.calls, [.save(Data("42".utf8), "key"), .fetch("key"), .clear])
        XCTAssertEqual(coding.scope, storage.scope)
    }

    // MARK: Scope

    func testScopeIsTheStorages() {
        XCTAssertEqual(makeStorage().scope, storage.scope)
    }

    // MARK: Helpers

    private func makeStorage(coder: any DataCoder = DataCoderMock()) -> AsyncCodingStorage<AsyncDataStorageMock> {
        AsyncCodingStorage(storage: storage, coder: coder)
    }
}
