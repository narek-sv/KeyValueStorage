//
//  KeychainBackingStoreMock.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation
import Security
@testable import KeyValueStorage

/// An in-memory keychain that matches queries as the real one does: a query without an access group or account
/// matches every group or account, one without `synchronizable` matches only local items, and an item can have no data.
/// Saves without an access group go to `defaultGroup`. Records every call, and answers a failing operation with its status.
/// Unchecked: used from one test at a time.
final class KeychainBackingStoreMock: KeychainBackingStore, @unchecked Sendable {
    enum Call: Equatable {
        case read(KeychainQuery)
        case add(KeychainQuery)
        case update(KeychainQuery, KeychainQuery)
        case remove(KeychainQuery)
    }

    enum Operation: Hashable {
        case read, add, update, remove
    }

    struct Item: Equatable {
        var service: String
        var account: String
        var accessGroup: String
        var synchronizable: Bool
        var accessibility: KeychainQuery.Accessibility?
        var data: Data?
    }

    let defaultGroup = "default.group"
    var items = [Item]()
    var failures = [Operation: KeychainOperationStatus]()
    /// Runs as an add starts, such as another caller adding the same item first.
    var beforeAdd: (() -> Void)?
    private(set) var calls = [Call]()

    func read(_ query: KeychainQuery) -> (KeychainOperationStatus, AnyObject?) {
        calls.append(.read(query))
        if let failure = failures[.read] {
            return (failure, nil)
        }

        guard let item = items.first(where: { matches($0, query) }) else {
            return (.notFound, nil)
        }

        return (.success, item.data as NSData?)
    }

    func add(_ attributes: KeychainQuery) -> KeychainOperationStatus {
        calls.append(.add(attributes))
        beforeAdd?()
        if let failure = failures[.add] {
            return failure
        }

        let item = Item(
            service: attributes.service ?? "",
            account: attributes.account ?? "",
            accessGroup: attributes.accessGroup ?? defaultGroup,
            synchronizable: attributes.synchronizable == .yes,
            accessibility: attributes.accessibility,
            data: attributes.valueData
        )

        guard !items.contains(where: { identity($0) == identity(item) }) else {
            return .duplicate
        }

        items.append(item)
        return .success
    }

    func update(_ query: KeychainQuery, with attributes: KeychainQuery) -> KeychainOperationStatus {
        calls.append(.update(query, attributes))
        if let failure = failures[.update] {
            return failure
        }

        let indices = items.indices.filter { matches(items[$0], query) }
        for index in indices {
            items[index].data = attributes.valueData
            items[index].accessibility = attributes.accessibility
        }

        return indices.isEmpty ? .notFound : .success
    }

    func remove(_ query: KeychainQuery) -> KeychainOperationStatus {
        calls.append(.remove(query))
        if let failure = failures[.remove] {
            return failure
        }

        let count = items.count
        items.removeAll { matches($0, query) }
        return items.count == count ? .notFound : .success
    }

    // MARK: Helpers

    private func matches(_ item: Item, _ query: KeychainQuery) -> Bool {
        query.service.map { $0 == item.service } ?? true
            && query.account.map { $0 == item.account } ?? true
            && query.accessGroup.map { $0 == item.accessGroup } ?? true
            && (query.synchronizable == .yes) == item.synchronizable
    }

    private func identity(_ item: Item) -> [String] {
        [item.service, item.account, item.accessGroup, "\(item.synchronizable)"]
    }
}
