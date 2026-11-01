//
//  FileItemErrorTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class FileItemErrorTests: XCTestCase {
    func testCodesMapToTheirCases() {
        XCTAssertEqual(FileItemError(code: ENOENT), .notFound)
        XCTAssertEqual(FileItemError(code: EPERM), .notPermitted)
        for code in [EACCES, ENOTDIR, ENAMETOOLONG, ELOOP, EIO, EINVAL, 0, -1] {
            XCTAssertEqual(FileItemError(code: code), .other(code), "\(code)")
        }
    }

    func testEveryCaseKeepsItsCode() {
        for code in [ENOENT, EPERM, EACCES, ENOTDIR, ENAMETOOLONG, ELOOP, EIO, EINVAL, 0, -1] {
            XCTAssertEqual(FileItemError(code: code).code, code)
        }
    }

    func testModesMapToTheirTypes() {
        let types: [(mode_t, FileAttributeType)] = [
            (S_IFREG, .typeRegular),
            (S_IFDIR, .typeDirectory),
            (S_IFLNK, .typeSymbolicLink),
            (S_IFSOCK, .typeSocket),
            (S_IFCHR, .typeCharacterSpecial),
            (S_IFBLK, .typeBlockSpecial),
            (S_IFIFO, .typeUnknown),
            (0, .typeUnknown)
        ]

        for (type, expected) in types {
            // The permission bits never change the type
            for permissions in [mode_t(0), 0o644, 0o777, 0o4755] {
                XCTAssertEqual(FileAttributeType(mode: type | permissions), expected, "\(type) \(permissions)")
            }
        }
    }
}
