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
    private let locator = FixedIdentifierKeychainLocator()

    // MARK: Services

    func testServices() {
        let services: [(KeychainStorage.Scope, String)] = [
            (.own(namespace: "auth"), "com.test.App:auth:w"),
            (.own(namespace: ""), "com.test.App::w"),
            (.own(namespace: "a/b%:"), "com.test.App:a%2Fb%25%3A:w"),
            (.own(namespace: "/\u{301}"), "com.test.App:%2F\u{301}:w"),
            (.appGroup(id: "group.com.app", namespace: "auth"), "group.com.app/auth/w"),
            (.appGroup(id: "group.com.app", namespace: ""), "group.com.app//w"),
            (.appGroup(id: "a/b:", namespace: "c/d"), "a%2Fb%3A/c%2Fd/w"),
            (.iCloud(.own, namespace: "auth"), "com.test.App:auth:w"),
            (.iCloud(.appGroup(id: "group.com.app"), namespace: "auth"), "group.com.app/auth/w")
        ]

        for (scope, service) in services {
            assertBytes(locator.service(for: scope), service)
        }
    }

    func testTheAppsIdentifierIsItsIdentifierEscaped() {
        let services = ["com.test.App", "a:b/c%", "", "my tool"].map { identifier in
            locator.identifier = identifier
            return locator.service(for: .own(namespace: "ns"))
        }

        XCTAssertEqual(services, ["com.test.App:ns:w", "a%3Ab%2Fc%25:ns:w", ":ns:w", "my tool:ns:w"])
    }

    func testEveryProtectionHasItsOwnService() {
        let protections: [(KeychainStorage.Protection, String)] = [
            (.untilFirstUnlock, "u"),
            (.untilFirstUnlockThisDeviceOnly, "ud"),
            (.whileLocked, "w"),
            (.whileLockedThisDeviceOnly, "wd"),
            (.whileLockedOrWithoutPasscode, "p")
        ]

        for (protection, name) in protections {
            XCTAssertEqual(locator.service(for: .own(protection: protection, namespace: "ns")), "com.test.App:ns:\(name)")
            XCTAssertEqual(locator.service(for: .appGroup(id: "g", protection: protection, namespace: "ns")), "g/ns/\(name)")
        }

        XCTAssertEqual(locator.service(for: .iCloud(.own, protection: .untilFirstUnlock, namespace: "ns")), "com.test.App:ns:u")
        XCTAssertEqual(locator.service(for: .iCloud(.appGroup(id: "g"), protection: .untilFirstUnlock, namespace: "ns")), "g/ns/u")
    }

    func testNoTwoLocalScopesShareAService() {
        // `.own` queries reach every access group, so its services must differ from every group's;
        // `.iCloud` shares its owner's services, for synced items
        let namespaces: [KeychainStorage.Namespace] = ["", "auth", "a/b", "a:b", "%", "%2F", "%3A", "g/auth", "g%2Fauth", "auth:w", "auth/w"]
        let protections: [KeychainStorage.Protection] = [.untilFirstUnlock, .untilFirstUnlockThisDeviceOnly, .whileLocked, .whileLockedThisDeviceOnly, .whileLockedOrWithoutPasscode]
        var scopes = [KeychainStorage.Scope]()
        for namespace in namespaces {
            for protection in protections {
                scopes.append(.own(protection: protection, namespace: namespace))
                scopes += ["g", "g/auth", "a:b", "com.test.App", ""].map { .appGroup(id: $0, protection: protection, namespace: namespace) }
            }
        }

        var owners = [[UInt8]: KeychainStorage.Scope]()
        for scope in scopes {
            let service = locator.service(for: scope)
            if let owner = owners.updateValue(scope, forKey: Array(service.utf8)) {
                XCTFail("\(owner) and \(scope) share \(service.debugDescription)")
            }
        }
    }

    func testTwoAppsNeverShareAService() {
        // Apps sharing a default access group
        let services = ["com.test.App", "com.test.App:ns", "com.test.app"].map { identifier in
            locator.identifier = identifier
            return locator.service(for: .own(namespace: "ns"))
        }

        XCTAssertEqual(Set(services).count, services.count)
    }

    func testTheLookupsReturnTheSystems() {
        let locator = DefaultKeychainLocator()

        XCTAssertEqual(locator.ownIdentifier, OwnIdentity.identifier)
    }

    // MARK: Access Groups And Accounts

    func testAccessGroups() {
        XCTAssertNil(locator.accessGroup(for: .own(namespace: "auth")))
        XCTAssertNil(locator.accessGroup(for: .iCloud(.own, namespace: "auth")))
        XCTAssertEqual(locator.accessGroup(for: .appGroup(id: "group.com.app", namespace: "auth")), "group.com.app")
        XCTAssertEqual(locator.accessGroup(for: .iCloud(.appGroup(id: "group.com.app"), namespace: "auth")), "group.com.app")
    }

    func testAccountsAreTheKeysExactBytes() {
        for key in ["", "key", "Key", "a/b", "a:b", "\u{E9}", "e\u{301}", "🙂"] {
            assertBytes(locator.account(forKey: .init(key), in: .default), key)
        }
    }
}

/// The default locator with the app's identifier fixed.
private final class FixedIdentifierKeychainLocator: DefaultKeychainLocator {
    var identifier = "com.test.App"

    override var ownIdentifier: String {
        identifier
    }
}
