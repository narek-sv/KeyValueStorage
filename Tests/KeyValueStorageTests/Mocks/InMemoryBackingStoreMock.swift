//
//  InMemoryBackingStoreMock.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import Foundation
@testable import KeyValueStorage

/// Buckets of its own, unlike the default, which the whole process shares; records every call.
final class InMemoryBackingStoreMock: InMemoryBackingStore {
    enum Call: Equatable {
        case read(String, String)
        case write(Data, String, String)
        case remove(String, String)
        case removeAll(String)
    }

    var buckets = [String: [String: Data]]()
    private(set) var calls = [Call]()

    func read(forKey key: String, in bucket: String) -> Data? {
        calls.append(.read(key, bucket))
        return buckets[bucket]?[key]
    }

    func write(_ data: Data, forKey key: String, in bucket: String) {
        calls.append(.write(data, key, bucket))
        buckets[bucket, default: [:]][key] = data
    }

    func remove(forKey key: String, in bucket: String) {
        calls.append(.remove(key, bucket))
        buckets[bucket]?[key] = nil
    }

    func removeAll(in bucket: String) {
        calls.append(.removeAll(bucket))
        buckets[bucket] = nil
    }
}
