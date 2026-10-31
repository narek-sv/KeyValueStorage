//
//  Assertions.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 28.10.26.
//

import XCTest
import Foundation

/// Fails unless `body` throws an error of `expected`'s type that prints like it; give `.other` the instance the mock throws.
/// - Note: Checks the dynamic type: without `FullTypedThrows`, Swift infers `body` as throwing `any Error`.
func assertThrows<Value>(
    _ expected: any Error,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () throws -> Value
) {
    do {
        let value = try body()
        XCTFail("Expected \(expected), got \(value)", file: file, line: line)
    } catch {
        XCTAssertTrue(type(of: error) == type(of: expected), "Expected a \(type(of: expected)), got \(type(of: error))", file: file, line: line)
        XCTAssertEqual(String(reflecting: error), String(reflecting: expected), file: file, line: line)
    }
}

/// `assertThrows` for `async` code.
func assertThrows<Value>(
    _ expected: any Error,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () async throws -> Value
) async {
    do {
        let value = try await body()
        XCTFail("Expected \(expected), got \(value)", file: file, line: line)
    } catch {
        XCTAssertTrue(type(of: error) == type(of: expected), "Expected a \(type(of: expected)), got \(type(of: error))", file: file, line: line)
        XCTAssertEqual(String(reflecting: error), String(reflecting: expected), file: file, line: line)
    }
}

/// Fails unless `actual` has exactly `expected`'s UTF-8 bytes: `XCTAssertEqual` takes `"é"` and `"e\u{301}"` for one.
func assertBytes(_ actual: String?, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual.map { Array($0.utf8) }, Array(expected.utf8), "\(actual.debugDescription) isn't \(expected.debugDescription)", file: file, line: line)
}

/// The REFACTOR_PLAN.md §4.5 laws within one scope: round trip (L1), no shared names (L2), no claimed foreign names (L4).
/// - Note: Keys compare by scalars: storages keep `"é"` and `"e\u{301}"` apart, though Swift's `==` doesn't.
/// - Parameter sameName: Whether the system sees two names as one, such as a case-insensitive volume.
func assertLocatorLaws(
    keys: [String],
    foreignNames: [String],
    storedName: (String) throws -> String,
    key: (String) -> String?,
    sameName: (String, String) -> Bool = { $0 == $1 },
    file: StaticString = #filePath,
    line: UInt = #line
) {
    var named = [(key: String, name: String)]()
    for candidate in keys {
        let name: String
        do {
            name = try storedName(candidate)
        } catch {
            XCTFail("\(candidate.debugDescription) is a valid key, but \(error)", file: file, line: line)
            continue
        }

        XCTAssertEqual(key(name).map { Array($0.unicodeScalars) }, Array(candidate.unicodeScalars),
                       "L1: \(candidate.debugDescription) doesn't map back", file: file, line: line)
        for other in named where !other.key.unicodeScalars.elementsEqual(candidate.unicodeScalars) && sameName(other.name, name) {
            XCTFail("L2: \(other.key.debugDescription) and \(candidate.debugDescription) share \(name.debugDescription)", file: file, line: line)
        }

        named.append((candidate, name))
    }

    for name in foreignNames {
        XCTAssertNil(key(name), "L4: \(name.debugDescription) is claimed", file: file, line: line)
    }
}

/// A Cocoa error wrapping a POSIX one, as Foundation's file APIs throw them.
func fileSystemError(_ code: CocoaError.Code, _ posix: POSIXErrorCode? = nil) -> NSError {
    var userInfo = [String: Any]()
    if let posix {
        userInfo[NSUnderlyingErrorKey] = NSError(domain: NSPOSIXErrorDomain, code: Int(posix.rawValue))
    }

    return NSError(domain: NSCocoaErrorDomain, code: code.rawValue, userInfo: userInfo)
}
