//
//  Lock.swift
//  KeyValueStorage
//
//  Created by nsahakyan@servicetitan.com on 17.10.26.
//

import Foundation
#if canImport(os)
import os
#endif

// MARK: - Lock

/// Internal mutual-exclusion lock.
/// Uses OSAllocatedUnfairLock where available, otherwise falls back to NSLock.
final class Lock: @unchecked Sendable {
    private let backend: LockBackend
    
    init() {
        #if canImport(os)
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            backend = UnfairLockBackend()
            return
        }
        #endif
        backend = NSLockBackend()
    }
    
    func withLock<R>(_ body: () throws -> R) rethrows -> R {
        try backend.withLock(body)
    }
}

// MARK: - LockBackend

private protocol LockBackend: AnyObject {
    func withLock<R>(_ body: () throws -> R) rethrows -> R
}

// MARK: - NSLockBackend

private final class NSLockBackend: LockBackend {
    private let lock = NSLock()
    
    func withLock<R>(_ body: () throws -> R) rethrows -> R {
        try lock.withLock(body)
    }
}

// MARK: - UnfairLockBackend

#if canImport(os)
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private final class UnfairLockBackend: LockBackend {
    private let lock = OSAllocatedUnfairLock()
    
    func withLock<R>(_ body: () throws -> R) rethrows -> R {
        try lock.withLockUnchecked(body)
    }
}
#endif
