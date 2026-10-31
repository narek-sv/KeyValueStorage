//
//  CodingRoundTripTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

/// Real values through each coder and both coding storages, over a real `InMemoryStorage`.
final class CodingRoundTripTests: XCTestCase {
    private typealias Key<Value: CodingValue> = CodingStorageKey<InMemoryStorage, Value>

    private let structValue = CustomStruct(int: 3, string: "3", date: Date(timeIntervalSince1970: 3), inner: [Inner(id: UUID())])
    private let classValue = CustomClass(int: 4, string: "ключ 🔑", date: Date(timeIntervalSince1970: 4), inner: [])
    private let actorValue = CustomActor(int: 5, string: "", date: Date(timeIntervalSince1970: 5), inner: [Inner(id: UUID()), Inner(id: UUID())])
    private let enumValues: [CustomEnum] = [.case1(6), .case2("seven"), .case3(date: Date(timeIntervalSince1970: 8))]

    override func tearDown() {
        for name in Self.coders.map(\.name) {
            InMemoryStorage(scope: .own(namespace: .init("roundTrip-\(name)"))).clear()
        }
    }

    // MARK: Round Trips

    func testEveryKindOfValueRoundTripsThroughEachCoder() throws {
        for (name, coder) in Self.coders {
            let storage = CodingStorage(storage: InMemoryStorage(scope: .own(namespace: .init("roundTrip-\(name)"))), coder: coder)

            try assertRoundTrip(structValue, storage, name)
            try assertRoundTrip(classValue, storage, name)
            try assertRoundTrip(actorValue, storage, name)
            for value in enumValues {
                try assertRoundTrip(value, storage, name)
            }

            try assertRoundTrip(0, storage, name)
            try assertRoundTrip(Int.min, storage, name)
            try assertRoundTrip(Int.max, storage, name)
            try assertRoundTrip(-3.5, storage, name)
            try assertRoundTrip(true, storage, name)
            try assertRoundTrip(false, storage, name)
            try assertRoundTrip("", storage, name)
            try assertRoundTrip("ключ 🔑 e\u{301}", storage, name)
            try assertRoundTrip(Data(), storage, name)
            try assertRoundTrip(Data([0x00, 0xFF, 0x10]), storage, name)
            try assertRoundTrip(Date(timeIntervalSince1970: 3), storage, name)
            try assertRoundTrip(UUID(), storage, name)
            try assertRoundTrip([Int](), storage, name)
            try assertRoundTrip([1, 2, 3], storage, name)
            try assertRoundTrip(["a": 1, "b": 2], storage, name)
            try assertRoundTrip([[structValue]], storage, name)
            try assertRoundTrip(Optional(42), storage, name)
            try assertRoundTrip(Optional("token"), storage, name)
        }
    }

    func testTheAsyncCodingStorageRoundTripsLikeTheSyncOne() async throws {
        for (name, coder) in Self.coders {
            // Given
            let storage = AsyncCodingStorage(storage: InMemoryStorage(scope: .own(namespace: .init("roundTrip-\(name)"))), coder: coder)
            let structKey = Key<CustomStruct>(key: "struct")
            let enumKey = Key<[CustomEnum]>(key: "enums")

            // When
            try await storage.save(structValue, forKey: structKey)
            try await storage.set(enumValues, forKey: enumKey)
            let fetchedStruct = try await storage.fetch(forKey: structKey)
            let fetchedEnums = try await storage.fetch(forKey: enumKey)
            try await storage.set(nil, forKey: structKey)
            try await storage.delete(forKey: enumKey)

            // Then
            XCTAssertEqual(fetchedStruct, structValue, name)
            XCTAssertEqual(fetchedEnums, enumValues, name)
            let deletedStruct = try await storage.fetch(forKey: structKey)
            let deletedEnums = try await storage.fetch(forKey: enumKey)
            XCTAssertNil(deletedStruct, name)
            XCTAssertNil(deletedEnums, name)
        }
    }

    func testClearRemovesEveryValueOfTheScope() throws {
        // Given
        let storage = CodingStorage(storage: InMemoryStorage(scope: .own(namespace: "roundTrip-json")), coder: JSONDataCoder())
        let other = CodingStorage(storage: InMemoryStorage(scope: .own(namespace: "roundTrip-raw")), coder: JSONDataCoder())
        try storage.save(structValue, forKey: Key(key: "struct"))
        try storage.save(classValue, forKey: Key(key: "class"))
        try other.save(1, forKey: Key(key: "kept"))

        // When
        try storage.clear()

        // Then
        XCTAssertNil(try storage.fetch(forKey: Key<CustomStruct>(key: "struct")))
        XCTAssertNil(try storage.fetch(forKey: Key<CustomClass>(key: "class")))
        XCTAssertEqual(try other.fetch(forKey: Key<Int>(key: "kept")), 1)
    }

    // MARK: Value Types

    func testFetchDecodesAsTheKeysValueType() throws {
        // Given
        let coder = TypeRecordingCoder()
        let storage = CodingStorage(storage: InMemoryStorage(scope: .own(namespace: "roundTrip-json")), coder: coder)
        try storage.save(42, forKey: Key<Int>(key: "int"))
        try storage.save(Optional(42), forKey: Key<Int?>(key: "optional"))

        // When
        let int = try storage.fetch(forKey: Key<Int>(key: "int"))
        let optional = try storage.fetch(forKey: Key<Int?>(key: "optional"))

        // Then: never the optional the return type would suggest
        XCTAssertEqual(int, 42)
        XCTAssertEqual(optional, 42)
        XCTAssertEqual(coder.decodedTypes, [ObjectIdentifier(Int.self), ObjectIdentifier(Int?.self)])
    }

    func testJSONNullIsACodingErrorForANonOptionalType() throws {
        // Given
        let data = InMemoryStorage(scope: .own(namespace: "roundTrip-json"))
        data.save(Data("null".utf8), forKey: "key")
        let storage = CodingStorage(storage: data, coder: JSONDataCoder())

        // When - Then
        XCTAssertThrowsError(try storage.fetch(forKey: Key<Int>(key: "key"))) { error in
            guard case .coding(DecodingError.valueNotFound)? = error as? CodingStorageError<InMemoryStorage> else {
                return XCTFail("Unexpected error \(error)")
            }
        }
    }

    func testAnOptionalTypeTellsAStoredNilFromNoValue() throws {
        // Given
        let storage = CodingStorage(storage: InMemoryStorage(scope: .own(namespace: "roundTrip-json")), coder: JSONDataCoder())
        let key = Key<Int?>(key: "key")

        // When: `.some(nil)` is a value, saved as `null`; `nil` deletes
        try storage.set(.some(nil), forKey: key)
        let stored = try storage.fetch(forKey: key)
        try storage.set(nil, forKey: key)
        let deleted = try storage.fetch(forKey: key)

        // Then
        XCTAssertEqual(stored, .some(nil))
        XCTAssertEqual(deleted, nil as Int??)
    }

    func testAValueSavedAsAnotherTypeIsACodingError() throws {
        for (name, coder) in Self.coders {
            // Given
            let storage = CodingStorage(storage: InMemoryStorage(scope: .own(namespace: .init("roundTrip-\(name)"))), coder: coder)
            try storage.save(structValue, forKey: Key(key: "key"))

            // When - Then
            XCTAssertThrowsError(try storage.fetch(forKey: Key<Int>(key: "key")), name) { error in
                guard case .coding? = error as? CodingStorageError<InMemoryStorage> else {
                    return XCTFail("\(name): unexpected error \(error)")
                }
            }
        }
    }

    // MARK: Helpers

    private static let coders: [(name: String, coder: any DataCoder)] = [
        ("raw", RawDataCoder()),
        ("json", JSONDataCoder()),
        ("propertyList", PropertyListDataCoder())
    ]

    private func assertRoundTrip<Value: CodingValue & Equatable>(
        _ value: Value,
        _ storage: CodingStorage<InMemoryStorage>,
        _ coder: String,
        line: UInt = #line
    ) throws {
        let key = Key<Value>(key: "\(Value.self)")
        try storage.save(value, forKey: key)
        XCTAssertEqual(try storage.fetch(forKey: key), value, "\(coder): \(value)", line: line)
        try storage.delete(forKey: key)
        XCTAssertNil(try storage.fetch(forKey: key), "\(coder): \(value)", line: line)
    }
}

// MARK: - Values

extension CodingRoundTripTests {
    struct CustomStruct: Codable, Equatable {
        let int: Int
        let string: String
        let date: Date
        let inner: [Inner]
    }

    final class CustomClass: Codable, Equatable, Sendable {
        let int: Int
        let string: String
        let date: Date
        let inner: [Inner]

        init(int: Int, string: String, date: Date, inner: [Inner]) {
            self.int = int
            self.string = string
            self.date = date
            self.inner = inner
        }

        static func == (lhs: CustomClass, rhs: CustomClass) -> Bool {
            lhs.int == rhs.int && lhs.string == rhs.string && lhs.date == rhs.date && lhs.inner == rhs.inner
        }
    }

    /// The decoder is only used during the call, so passing it to the actor's initializer is safe.
    actor CustomActor: Encodable, @preconcurrency Decodable, Equatable {
        let int: Int
        let string: String
        let date: Date
        let inner: [Inner]

        init(int: Int, string: String, date: Date, inner: [Inner]) {
            self.int = int
            self.string = string
            self.date = date
            self.inner = inner
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.int = try container.decode(Int.self, forKey: .int)
            self.string = try container.decode(String.self, forKey: .string)
            self.date = try container.decode(Date.self, forKey: .date)
            self.inner = try container.decode([Inner].self, forKey: .inner)
        }

        static func == (lhs: CustomActor, rhs: CustomActor) -> Bool {
            lhs.int == rhs.int && lhs.string == rhs.string && lhs.date == rhs.date && lhs.inner == rhs.inner
        }

        nonisolated func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(int, forKey: .int)
            try container.encode(string, forKey: .string)
            try container.encode(date, forKey: .date)
            try container.encode(inner, forKey: .inner)
        }

        enum CodingKeys: CodingKey {
            case int, string, date, inner
        }
    }

    enum CustomEnum: Codable, Equatable {
        case case1(Int)
        case case2(String)
        case case3(date: Date)
    }

    struct Inner: Codable, Equatable {
        let id: UUID
    }
}

// MARK: - TypeRecordingCoder

/// JSON, recording the types it's asked to decode.
private final class TypeRecordingCoder: DataCoder, @unchecked Sendable {
    private let lock = NSLock()
    private var types = [ObjectIdentifier]()

    var decodedTypes: [ObjectIdentifier] {
        lock.withLock { types }
    }

    func encode<Value: CodingValue>(_ value: Value) throws -> Data {
        try JSONDataCoder().encode(value)
    }

    func decode<Value: CodingValue>(_ data: Data) throws -> Value {
        lock.withLock { types.append(ObjectIdentifier(Value.self)) }
        return try JSONDataCoder().decode(data)
    }
}
