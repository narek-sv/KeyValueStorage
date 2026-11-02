//
//  Waiting.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 02.11.26.
//

import XCTest
import Foundation

/// Returns once `condition` holds, letting other tasks run meanwhile; fails the test and throws after `timeout` seconds.
func waitUntil(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line,
               _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else {
            XCTFail("The condition didn't hold within \(timeout) s", file: file, line: line)
            throw WaitTimedOut()
        }

        await Task.yield()
    }
}

/// The task's value once it finishes; fails the test and throws if it doesn't finish within `timeout` seconds, so a call or
/// a move that waits forever fails the test instead of hanging the run.
func waitForValue<Success: Sendable, Failure: Error>(of task: Task<Success, Failure>, timeout: TimeInterval = 5,
                                                     file: StaticString = #filePath, line: UInt = #line) async throws -> Success {
    let result = TaskResult<Success>()
    Task {
        result.set(await task.result.mapError { $0 as any Error })
    }

    try await waitUntil(timeout: timeout, file: file, line: line) { result.get() != nil }
    return try XCTUnwrap(result.get(), file: file, line: line).get()
}

/// Thrown at `waitUntil`'s timeout, so the test stops there.
struct WaitTimedOut: Error { }

/// A task's result, set by the task that waits for it and read by the test.
private final class TaskResult<Success: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Success, any Error>?

    func set(_ result: Result<Success, any Error>) {
        lock.withLock { self.result = result }
    }

    func get() -> Result<Success, any Error>? {
        lock.withLock { result }
    }
}
