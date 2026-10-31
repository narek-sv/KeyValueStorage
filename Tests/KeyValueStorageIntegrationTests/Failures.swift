//
//  Failures.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.10.26.
//

import Foundation

/// Collects failures reported from any thread.
final class Failures: @unchecked Sendable {
    private let lock = NSLock()
    private var failures = [String]()

    var all: [String] {
        lock.withLock { failures }
    }

    func append(_ failure: String) {
        lock.withLock { failures.append(failure) }
    }
}
