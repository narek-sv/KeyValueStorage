//
//  PrivacyManifestTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 02.11.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class PrivacyManifestTests: XCTestCase {
    func testTheManifestDeclaresEveryRequiredReasonAPIWithItsReason() throws {
        // Given: the manifest as the package bundles it
        let url = try XCTUnwrap(Bundle.module.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])

        // When
        let declarations = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let reasons = declarations.reduce(into: [String: [String]]()) { reasons, declaration in
            reasons[declaration["NSPrivacyAccessedAPIType"] as? String ?? ""] = declaration["NSPrivacyAccessedAPITypeReasons"] as? [String]
        }

        // Then: User Defaults, and the file storage's `lstat`, which Apple lists among the file timestamp APIs
        XCTAssertEqual(reasons, [
            "NSPrivacyAccessedAPICategoryUserDefaults": ["C56D.1"],
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"]
        ])
    }
}
