//
//  KeyValueDataStorageTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class KeyValueDataStorageTests: XCTestCase {
    func testEveryDefaultScopeSharesTheLibrarysNamespace() {
        XCTAssertEqual(MockScope.defaultNamespace, "KeyValueStorage")
        XCTAssertEqual(FileStorage.Scope.default, .own(namespace: "KeyValueStorage"))
        XCTAssertEqual(InMemoryStorage.Scope.default, .own(namespace: "KeyValueStorage"))
    }

    func testSetSavesAValueAndDeletesNil() throws {
        // Given
        let storage = DataStorageMock(scope: .init(name: "set"))

        // When
        try storage.set(Data([1]), forKey: "key")
        try storage.set(nil, forKey: "key")

        // Then
        XCTAssertEqual(storage.calls, [.save(Data([1]), "key"), .delete("key")])
    }

    func testSetReportsTheStoragesError() {
        // Given
        let storage = DataStorageMock(scope: .init(name: "set"))
        storage.error = MockError(id: 1)

        // When - Then
        assertThrows(MockError(id: 1)) { try storage.set(Data([1]), forKey: "key") }
        assertThrows(MockError(id: 1)) { try storage.set(nil, forKey: "key") }
    }
}
