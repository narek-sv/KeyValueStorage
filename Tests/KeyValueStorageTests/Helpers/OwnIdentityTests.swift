//
//  OwnIdentityTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 01.11.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class OwnIdentityTests: XCTestCase {
    func testTheIdentifiersAreTheSystems() {
        XCTAssertEqual(OwnIdentity.bundleIdentifier, Bundle.main.bundleIdentifier)
        XCTAssertEqual(OwnIdentity.processName, ProcessInfo.processInfo.processName)
        XCTAssertFalse(OwnIdentity.processName.isEmpty)
    }

    func testTheIdentifierIsTheBundleIdentifierOrElseTheProcessName() {
        XCTAssertEqual(OwnIdentity.identifier, Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName)
    }
}
