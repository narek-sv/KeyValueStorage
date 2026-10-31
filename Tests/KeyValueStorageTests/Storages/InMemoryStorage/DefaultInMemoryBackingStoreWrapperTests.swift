//
//  DefaultInMemoryBackingStoreWrapperTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import XCTest
import Foundation
@testable import KeyValueStorage

/// The default backing store is shared by the whole process, so every test uses containers of its own.
final class DefaultInMemoryBackingStoreWrapperTests: XCTestCase {
    private let run = UUID().uuidString
    
    func testConcurrentAccessIsSerialized() {
        // Given: 8 threads, each pair sharing a container
        let containers = DefaultInMemoryBackingStoreWrapper()
        let threads = 8
        let iterations = 10_000
        let run = run

        // When
        DispatchQueue.concurrentPerform(iterations: threads) { thread in
            let container = "\(run)-c\(thread % 2)"
            for i in 0..<iterations {
                let key = "k\(thread)-\(i % 100)"
                containers.write(Data([UInt8(i % 256)]), forKey: key, in: container)
                _ = containers.read(forKey: key, in: container)
                if i % 10 == 0 {
                    containers.remove(forKey: key, in: container)
                }
                if i % 2_500 == 0 {
                    containers.removeAll(in: "\(run)-scratch\(thread)")
                }
            }
        }

        // Then: every key keeps its thread's last write, unless that write was removed
        for thread in 0..<threads {
            for j in 0..<100 {
                let last = iterations - 100 + j
                let value = containers.read(forKey: "k\(thread)-\(j)", in: "\(run)-c\(thread % 2)")
                XCTAssertEqual(value, last % 10 == 0 ? nil : Data([UInt8(last % 256)]))
            }
        }
    }

    /// A deallocator that writes back to the same containers re-locks, and crashes the test process,
    /// if overwritten or removed values are released while the lock is held.
    func testReleasedValuesAreFreedAfterUnlocking() {
        // Given: values whose deallocator writes to the same containers
        let containers = DefaultInMemoryBackingStoreWrapper()
        let container = "\(run)-c"
        let log = "\(run)-log"
        func reentrantData(_ byte: UInt8) -> Data {
            // Large enough not to be stored inline, so the deallocator runs only when the value is released
            let pointer = UnsafeMutableRawPointer.allocate(byteCount: 1024, alignment: 1)
            pointer.initializeMemory(as: UInt8.self, repeating: byte, count: 1024)
            return Data(bytesNoCopy: pointer, count: 1024, deallocator: .custom { pointer, _ in
                containers.write(Data([byte]), forKey: "released-\(byte)", in: log)
                pointer.deallocate()
            })
        }

        containers.write(reentrantData(1), forKey: "a", in: container)
        containers.write(reentrantData(2), forKey: "b", in: container)
        containers.write(reentrantData(3), forKey: "d", in: container)
        XCTAssertNil(containers.read(forKey: "released-1", in: log))

        // When
        containers.write(Data([9]), forKey: "a", in: container)
        containers.remove(forKey: "b", in: container)
        containers.removeAll(in: container)

        // Then
        XCTAssertEqual(containers.read(forKey: "released-1", in: log), Data([1]))
        XCTAssertEqual(containers.read(forKey: "released-2", in: log), Data([2]))
        XCTAssertEqual(containers.read(forKey: "released-3", in: log), Data([3]))
    }

    func testCanonicallyEquivalentKeysAndContainersAreDistinct() {
        // Given
        let containers = DefaultInMemoryBackingStoreWrapper()
        let precomposed = "\(run)-\u{E9}"
        let decomposed = "\(run)-e\u{301}"

        // When
        containers.write(Data([1]), forKey: "\u{E9}", in: precomposed)
        containers.write(Data([2]), forKey: "e\u{301}", in: precomposed)
        containers.write(Data([3]), forKey: "\u{E9}", in: decomposed)

        // Then
        XCTAssertEqual(containers.read(forKey: "\u{E9}", in: precomposed), Data([1]))
        XCTAssertEqual(containers.read(forKey: "e\u{301}", in: precomposed), Data([2]))
        XCTAssertEqual(containers.read(forKey: "\u{E9}", in: decomposed), Data([3]))
        XCTAssertNil(containers.read(forKey: "e\u{301}", in: decomposed))

        containers.remove(forKey: "e\u{301}", in: precomposed)
        XCTAssertEqual(containers.read(forKey: "\u{E9}", in: precomposed), Data([1]))
        XCTAssertNil(containers.read(forKey: "e\u{301}", in: precomposed))

        containers.removeAll(in: decomposed)
        XCTAssertEqual(containers.read(forKey: "\u{E9}", in: precomposed), Data([1]))
        XCTAssertNil(containers.read(forKey: "\u{E9}", in: decomposed))
    }

    func testBridgedStringsReachTheSameValues() {
        let containers = DefaultInMemoryBackingStoreWrapper()
        let container = "\(run)-bridged"
        containers.write(Data([1]), forKey: "Caf\u{E9}", in: container)
        XCTAssertEqual(containers.read(forKey: NSString(string: "Caf\u{E9}") as String, in: NSString(string: container) as String), Data([1]))
    }
}
