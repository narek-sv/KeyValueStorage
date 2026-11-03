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
    private typealias Factory = UnifiedStorage.Factory
    /// Another storage type with the mock's scopes, which the mock's modifiers leave alone.
    private typealias Isolated = IsolatedDataStorage<DataStorageMock>

    private let scope = MockScope(name: "factory")

    // MARK: Defaults

    func testTheDefaultFactoryCreatesTheStorageForTheScope() async throws {
        let storage: AsyncDataStorageMock = try await Factory.default.makeDataStorage(for: scope)
        XCTAssertEqual(storage.scope, scope)
    }

    func testTheDefaultFactoryCodesRawAndDoesntObserve() async throws {
        // Given
        let isolated = Isolated(DataStorageMock(scope: scope))

        // When
        let coder = Factory.default.makeCoder(for: isolated)
        let coding = await Factory.default.makeCodingStorage(for: isolated, coder: coder)
        try await coding.save("raw", forKey: CodingStorageKey(key: "key"))
        let observable = await Factory.default.makeObservableStorage(for: coding)

        // Then
        XCTAssertTrue(coder is RawDataCoder)
        let stored = try await isolated.fetch(forKey: "key")
        XCTAssertEqual(stored, Data("raw".utf8))
        XCTAssertNil(observable)
    }

    // MARK: Every Storage Type

    func testCoderCodesEveryStorageType() {
        // Given
        let factory = Factory.default.coder(JSONDataCoder())

        // When
        let mockCoder = factory.makeCoder(for: AsyncDataStorageMock(scope: scope))
        let isolatedCoder = factory.makeCoder(for: Isolated(DataStorageMock(scope: scope)))

        // Then
        XCTAssertTrue(mockCoder is JSONDataCoder)
        XCTAssertTrue(isolatedCoder is JSONDataCoder)
    }

    func testObservableObservesEveryStorageTypeThroughTheCodingStorageItsGiven() async throws {
        // Given
        let factory = Factory.default.observable()
        let coding = AsyncCodingStorage(storage: AsyncDataStorageMock(scope: scope))
        let key = CodingStorageKey<AsyncDataStorageMock, Int>(key: "key")

        // When
        let made = await factory.makeObservableStorage(for: coding)
        let observable = try XCTUnwrap(made)
        try await observable.save(1, forKey: key)
        let other = await factory.makeObservableStorage(for: AsyncCodingStorage(storage: Isolated(DataStorageMock(scope: scope))))

        // Then: it saved through the coding storage it was given, and the other type is observable too
        let fromCoding = try await coding.fetch(forKey: key)
        XCTAssertEqual(fromCoding, 1)
        XCTAssertNotNil(other)
    }

    func testObservableFalseObservesNone() async {
        let factory = Factory.default.observable().observable(false)
        let observable = await factory.makeObservableStorage(for: AsyncCodingStorage(storage: AsyncDataStorageMock(scope: scope)))
        XCTAssertNil(observable)
    }

    // MARK: One Storage Type

    func testEachModifierForAStorageTypeChangesItsStep() async throws {
        // Given
        let factory = Factory.default
            .dataStorage(for: AsyncDataStorageMock.self) { scope throws(MockError) in
                AsyncDataStorageMock(scope: .init(name: "made for \(scope.name)"))
            }
            .coder(JSONDataCoder(), for: AsyncDataStorageMock.self)
            .codingStorage(for: AsyncDataStorageMock.self) { storage, coder in
                TaggedCodingStorage(storage: storage, coder: coder)
            }
            .observableStorage(for: AsyncDataStorageMock.self) { coding in
                TaggedObservableStorage(coding)
            }

        // When
        let mock: AsyncDataStorageMock = try await factory.makeDataStorage(for: scope)
        let coder = factory.makeCoder(for: mock)
        let coding = await factory.makeCodingStorage(for: mock, coder: coder)
        let observable = await factory.makeObservableStorage(for: coding)
        try await coding.save("value", forKey: CodingStorageKey(key: "key"))

        // Then: each step is the modifier's, and the coding storage codes with the type's coder
        XCTAssertEqual(mock.scope, .init(name: "made for factory"))
        XCTAssertTrue(coder is JSONDataCoder)
        XCTAssertTrue(coding is TaggedCodingStorage<AsyncDataStorageMock>)
        XCTAssertTrue(observable is TaggedObservableStorage<AsyncDataStorageMock>)
        let stored = await mock.values["key"]
        XCTAssertEqual(stored, Data("\"value\"".utf8))
    }

    func testModifiersForAStorageTypeLeaveAnotherWithTheSameScopesAlone() async throws {
        // Given: every step changed for the mock
        let factory = Factory.default
            .dataStorage(for: AsyncDataStorageMock.self) { _ throws(MockError) in
                throw MockError(id: 1)
            }
            .coder(JSONDataCoder(), for: AsyncDataStorageMock.self)
            .codingStorage(for: AsyncDataStorageMock.self) { storage, coder in
                TaggedCodingStorage(storage: storage, coder: coder)
            }
            .observableStorage(for: AsyncDataStorageMock.self) { coding in
                TaggedObservableStorage(coding)
            }

        // When: the other storage type, which has the mock's scopes
        let isolated: Isolated = try await factory.makeDataStorage(for: scope)
        let coder = factory.makeCoder(for: isolated)
        let coding = await factory.makeCodingStorage(for: isolated, coder: coder)
        let observable = await factory.makeObservableStorage(for: coding)

        // Then: every default
        XCTAssertEqual(isolated.scope, scope)
        XCTAssertTrue(coder is RawDataCoder)
        XCTAssertTrue(type(of: coding) == AsyncCodingStorage<Isolated>.self)
        XCTAssertNil(observable)
    }

    func testDataStorageForAStorageTypePassesItsErrorOn() async {
        // Given
        let factory = Factory.default.dataStorage(for: AsyncDataStorageMock.self) { _ throws(MockError) in
            throw MockError(id: 3)
        }

        // When - Then
        await assertThrows(MockError(id: 3)) {
            let _: AsyncDataStorageMock = try await factory.makeDataStorage(for: scope)
        }
    }

    func testObservableForAStorageTypeTurnsItsObservationOnOrOff() async {
        // Given
        let on = Factory.default.observable(for: AsyncDataStorageMock.self)
        let off = Factory.default.observable().observable(false, for: AsyncDataStorageMock.self)
        let mock = AsyncCodingStorage(storage: AsyncDataStorageMock(scope: scope))
        let isolated = AsyncCodingStorage(storage: Isolated(DataStorageMock(scope: scope)))

        // When
        let mockOn = await on.makeObservableStorage(for: mock)
        let isolatedOn = await on.makeObservableStorage(for: isolated)
        let mockOff = await off.makeObservableStorage(for: mock)
        let isolatedOff = await off.makeObservableStorage(for: isolated)

        // Then
        XCTAssertNotNil(mockOn)
        XCTAssertNil(isolatedOn)
        XCTAssertNil(mockOff)
        XCTAssertNotNil(isolatedOff)
    }

    // MARK: Order

    func testTheLastModifierDecides() {
        // Given
        let typeLast = Factory.default.coder(JSONDataCoder()).coder(PropertyListDataCoder(), for: AsyncDataStorageMock.self)
        let everyTypeLast = Factory.default.coder(PropertyListDataCoder(), for: AsyncDataStorageMock.self).coder(JSONDataCoder())
        let mock = AsyncDataStorageMock(scope: scope)
        let isolated = Isolated(DataStorageMock(scope: scope))

        // When - Then: the type's coder only where it comes last
        XCTAssertTrue(typeLast.makeCoder(for: mock) is PropertyListDataCoder)
        XCTAssertTrue(typeLast.makeCoder(for: isolated) is JSONDataCoder)
        XCTAssertTrue(everyTypeLast.makeCoder(for: mock) is JSONDataCoder)
        XCTAssertTrue(everyTypeLast.makeCoder(for: isolated) is JSONDataCoder)
    }

    func testEachModifierMakesANewFactory() {
        // Given
        let json = Factory.default.coder(JSONDataCoder())

        // When
        let propertyList = json.coder(PropertyListDataCoder())

        // Then: the factory it was added to is unchanged
        let mock = AsyncDataStorageMock(scope: scope)
        XCTAssertTrue(json.makeCoder(for: mock) is JSONDataCoder)
        XCTAssertTrue(propertyList.makeCoder(for: mock) is PropertyListDataCoder)
    }

    // MARK: Modifiers of Your Own

    func testAModifierOfYourOwnGetsWhatTheOnesBeforeItMakeForEveryType() async throws {
        // Given: a modifier that counts creations, after modifiers it doesn't change
        let count = Counter()
        let factory = Factory.default
            .dataStorage(for: AsyncDataStorageMock.self) { scope throws(MockError) in
                AsyncDataStorageMock(scope: .init(name: "made for \(scope.name)"))
            }
            .coder(JSONDataCoder())
            .observable()
            .modifier(CountCreations(count: count))

        // When
        let mock: AsyncDataStorageMock = try await factory.makeDataStorage(for: scope)
        let isolated: Isolated = try await factory.makeDataStorage(for: scope)
        let coder = factory.makeCoder(for: mock)
        let coding = await factory.makeCodingStorage(for: mock, coder: coder)
        let observable = await factory.makeObservableStorage(for: coding)

        // Then: it counted both types' creations, and every step is what the modifiers before it make
        XCTAssertEqual(count.value, 2)
        XCTAssertEqual(mock.scope, .init(name: "made for factory"))
        XCTAssertEqual(isolated.scope, scope)
        XCTAssertTrue(coder is JSONDataCoder)
        XCTAssertTrue(type(of: coding) == AsyncCodingStorage<AsyncDataStorageMock>.self)
        XCTAssertNotNil(observable)
    }

    func testAModifierOfYourOwnCanReplaceAStepForEveryType() async throws {
        // Given: modifiers for the mock, then one of your own that replaces their steps for every type
        let skipped = Counter()
        let factory = Factory.default
            .dataStorage(for: AsyncDataStorageMock.self) { scope throws(MockError) in
                skipped.increment()
                return AsyncDataStorageMock(scope: scope)
            }
            .observable(false, for: AsyncDataStorageMock.self)
            .modifier(CreateAndObserveEveryType())

        // When
        let mock: AsyncDataStorageMock = try await factory.makeDataStorage(for: scope)
        let isolated: Isolated = try await factory.makeDataStorage(for: scope)
        let mockObservable = await factory.makeObservableStorage(for: AsyncCodingStorage(storage: mock))
        let isolatedObservable = await factory.makeObservableStorage(for: AsyncCodingStorage(storage: isolated))

        // Then: its own for both types, and nothing the replaced modifiers would have made
        XCTAssertTrue(mockObservable is TaggedObservableStorage<AsyncDataStorageMock>)
        XCTAssertTrue(isolatedObservable is TaggedObservableStorage<Isolated>)
        XCTAssertEqual(skipped.value, 0)
    }
}

// MARK: - CountCreations

/// Counts the storages it creates, through the modifiers before it.
private struct CountCreations: UnifiedStorage.Factory.Modifier {
    let count: Counter

    func dataStorage<Storage: UnifiedStorable>(
        for scope: Storage.Scope,
        previous: () async throws(Storage.Error) -> Storage
    ) async throws(Storage.Error) -> Storage {
        count.increment()
        return try await previous()
    }
}

// MARK: - CreateAndObserveEveryType

/// Creates every storage with `init(scope:)` and observes it through `TaggedObservableStorage`, whatever the modifiers
/// before it do.
private struct CreateAndObserveEveryType: UnifiedStorage.Factory.Modifier {
    func dataStorage<Storage: UnifiedStorable>(
        for scope: Storage.Scope,
        previous: () async throws(Storage.Error) -> Storage
    ) async throws(Storage.Error) -> Storage {
        try await Storage(scope: scope)
    }

    func observableStorage<Storage: UnifiedStorable>(
        for coding: AsyncCodingStorage<Storage>,
        previous: () async -> ObservableStorage<Storage>?
    ) async -> ObservableStorage<Storage>? {
        TaggedObservableStorage(coding)
    }
}

// MARK: - Tagged Storages

/// A coding storage the tests can tell apart from the default one.
private final class TaggedCodingStorage<Storage: AsyncDataStorage>: AsyncCodingStorage<Storage>, @unchecked Sendable { }

/// An observable storage the tests can tell apart from the default one.
private final class TaggedObservableStorage<Storage: AsyncDataStorage & Sendable>: ObservableStorage<Storage>, @unchecked Sendable { }

// MARK: - Counter

/// A count any thread can increment.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
