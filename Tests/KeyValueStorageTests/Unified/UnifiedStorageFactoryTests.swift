//
//  UnifiedStorageFactoryTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class UnifiedStorageFactoryTests: XCTestCase {
    // MARK: Defaults

    func testTheDefaultFactoryCreatesTheStorageForTheScope() async throws {
        let storage: AsyncDataStorageMock = try await DefaultUnifiedStorageFactory().dataStorage(for: .init(name: "created"))
        XCTAssertEqual(storage.scope, .init(name: "created"))
    }

    func testTheDefaultFactoryCodesRawAndDoesntObserve() async throws {
        // Given
        let factory = DefaultUnifiedStorageFactory()
        let storage = DataStorageMock(scope: .init(name: "raw"))
        let isolated = IsolatedDataStorage(storage)

        // When
        let coding = await factory.codingStorage(for: isolated)
        try await coding.save("raw", forKey: CodingStorageKey(key: "key"))
        let observable = await factory.observableStorage(for: coding)

        // Then
        XCTAssertTrue(factory.coder(for: isolated) is RawDataCoder)
        let stored = try await isolated.fetch(forKey: "key")
        XCTAssertEqual(stored, Data("raw".utf8))
        XCTAssertNil(observable)
    }

    func testTheObservableFactoryObservesTheCodingStorageItsGiven() async throws {
        // Given
        let factory = ObservableUnifiedStorageFactory()
        let mock = AsyncDataStorageMock(scope: .init(name: "observed"))
        let coding = await factory.codingStorage(for: mock)

        // When
        let made = await factory.observableStorage(for: coding)
        let observable = try XCTUnwrap(made)
        try await observable.save(1, forKey: CodingStorageKey<AsyncDataStorageMock, Int>(key: "key"))

        // Then: it wrapped the coding storage it was given
        let fromCoding = try await coding.fetch(forKey: CodingStorageKey<AsyncDataStorageMock, Int>(key: "key"))
        XCTAssertEqual(fromCoding, 1)
        XCTAssertEqual(observable.scope, mock.scope)
        XCTAssertTrue(factory.coder(for: mock) is RawDataCoder)
    }

    // MARK: Overrides

    func testAFactoryOverridesOnlyWhatItChanges() async throws {
        // Given: a factory that changes only the coder
        let factory = JSONOnlyFactory()
        let mock = AsyncDataStorageMock(scope: .init(name: "json"))

        // When
        let coding = await factory.codingStorage(for: mock)
        try await coding.save("json", forKey: CodingStorageKey(key: "key"))

        // Then: the default coding storage used the overridden coder, and the other defaults stay
        let stored = await mock.values["key"]
        XCTAssertEqual(stored, Data("\"json\"".utf8))
        let observable = await factory.observableStorage(for: coding)
        XCTAssertNil(observable)
    }
}

// MARK: - JSONOnlyFactory

/// Changes the coder and nothing else.
private struct JSONOnlyFactory: UnifiedStorageFactory {
    func coder<Storage: UnifiedStorable>(for storage: Storage) -> any DataCoder {
        JSONDataCoder()
    }
}
