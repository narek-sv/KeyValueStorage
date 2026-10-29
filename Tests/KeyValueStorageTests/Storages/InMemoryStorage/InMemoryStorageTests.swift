//
//  InMemoryStorageTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class InMemoryStorageTests: XCTestCase {
    private let backingStore = InMemoryBackingStoreMock()
    private let locator = InMemoryLocatorStub()
    private let scope = InMemoryStorage.Scope.app(namespace: .bucket(named: "name"))
    private let data = Data([0xAA, 0xBB])

    // MARK: Locator

    func testOperationsUseExactlyTheLocatorsNames() {
        // Given
        let storage = makeStorage()

        // When
        storage.save(data, forKey: "key")
        let fetched = storage.fetch(forKey: "key")
        storage.delete(forKey: "key")
        storage.clear()

        // Then
        XCTAssertEqual(fetched, data)
        XCTAssertEqual(backingStore.calls, [
            .write(data, "located-key", "located-bucket"),
            .read("located-key", "located-bucket"),
            .remove("located-key", "located-bucket"),
            .removeAll("located-bucket")
        ])
        XCTAssertEqual(locator.calls, [.bucket(scope)] + Array(repeating: .storedKey("key", scope), count: 3))
    }

    func testScopeIsTheOneGiven() {
        XCTAssertEqual(makeStorage().scope, scope)
    }

    // MARK: Values

    func testClearEmptiesOnlyTheScopesBucket() {
        // Given
        backingStore.buckets = ["located-bucket": ["located-key": data], "other": ["located-key": data]]

        // When
        makeStorage().clear()

        // Then
        XCTAssertEqual(backingStore.buckets, ["other": ["located-key": data]])
    }

    func testSetSavesAValueAndDeletesNil() {
        // Given
        let storage = makeStorage()

        // When
        storage.set(data, forKey: "key")
        let saved = storage.fetch(forKey: "key")
        storage.set(nil, forKey: "key")

        // Then
        XCTAssertEqual(saved, data)
        XCTAssertNil(storage.fetch(forKey: "key"))
    }

    func testScopesNeverReachEachOthersValues() {
        // Given: the root, the empty name, and names that differ only in case or in how `é` is written,
        // in the process-wide store, so the names are this test's own
        let run = UUID().uuidString
        let names: [String?] = [nil, "", "a", "A", "\u{E9}", "e\u{301}"]
        let storages = names.map { name in
            InMemoryStorage(scope: .app(namespace: name.map { .bucket(named: run + $0) }), backingStore: DefaultInMemoryBackingStoreWrapper(),
                            locator: DefaultInMemoryLocator())
        }
        let root = storages[0]
        let key = run + "\u{E9}"
        let otherKey = run + "e\u{301}"
        defer { storages.forEach { $0.clear() } }

        // When
        for (index, storage) in storages.enumerated() {
            storage.save(Data([UInt8(index)]), forKey: key)
        }

        root.save(Data([9]), forKey: otherKey)

        // Then: keys, too, are their exact bytes
        for (index, storage) in storages.enumerated() {
            XCTAssertEqual(storage.fetch(forKey: key), Data([UInt8(index)]), "\(names[index].debugDescription)")
        }

        XCTAssertEqual(root.fetch(forKey: otherKey), Data([9]))

        // When
        storages[2].clear()

        // Then
        XCTAssertNil(storages[2].fetch(forKey: key))
        XCTAssertEqual(storages[3].fetch(forKey: key), Data([3]))
    }

    // MARK: Helpers

    private func makeStorage() -> InMemoryStorage {
        InMemoryStorage(scope: scope, backingStore: backingStore, locator: locator)
    }
}
