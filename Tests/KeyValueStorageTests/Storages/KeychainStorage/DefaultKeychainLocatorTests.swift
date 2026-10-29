//
//  DefaultKeychainLocatorTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

final class DefaultKeychainLocatorTests: XCTestCase {
    private let locator = DefaultKeychainLocator()

    // MARK: Services

    func testServices() {
        let services: [(KeychainStorage.Scope, String)] = [
            (.app(), ""),
            (.app(namespace: .service(named: "auth")), "auth"),
            (.app(namespace: .service(named: "")), "%"),
            (.app(namespace: .service(named: "a/b%")), "a%2Fb%25"),
            (.app(namespace: .service(named: "/\u{301}")), "%2F\u{301}"),
            (.appGroup(groupId: "group.com.app"), "group.com.app/"),
            (.appGroup(groupId: "group.com.app", namespace: .service(named: "auth")), "group.com.app/auth"),
            (.appGroup(groupId: "group.com.app", namespace: .service(named: "")), "group.com.app/%"),
            (.appGroup(groupId: "a/b", namespace: .service(named: "c/d")), "a%2Fb/c%2Fd")
        ]

        for (scope, service) in services {
            XCTAssertTrue(locator.service(for: scope).utf8.elementsEqual(service.utf8), "\(scope) → \(locator.service(for: scope).debugDescription)")
        }
    }

    func testNoTwoScopesShareAService() {
        // App scopes' queries reach every access group, so their services must differ from every App Group's
        let names = [nil, "", "auth", "a/b", "%", "%2F", "group.com.app/auth", "group.com.app%2Fauth"]
        let scopes = names.map { name in KeychainStorage.Scope.app(namespace: name.map { .service(named: $0) }) }
            + ["group.com.app", "a/b", "a", ""].flatMap { group in names.map { name in .appGroup(groupId: group, namespace: name.map { .service(named: $0) }) } }
        var owners = [[UInt8]: KeychainStorage.Scope]()

        for scope in scopes {
            let service = locator.service(for: scope)
            if let owner = owners.updateValue(scope, forKey: Array(service.utf8)) {
                XCTFail("\(owner) and \(scope) share \(service.debugDescription)")
            }
        }
    }

    // MARK: Access Groups And Accounts

    func testAccessGroups() {
        XCTAssertNil(locator.accessGroup(for: .app(namespace: .service(named: "auth"))))
        XCTAssertEqual(locator.accessGroup(for: .appGroup(groupId: "group.com.app", namespace: .service(named: "auth"))), "group.com.app")
    }

    func testAccountsAreTheKeysExactBytes() {
        for key in ["", "key", "Key", "a/b", "\u{E9}", "e\u{301}", "🙂"] {
            XCTAssertTrue(locator.account(forKey: key, in: .default).utf8.elementsEqual(key.utf8), key.debugDescription)
        }
    }
}
