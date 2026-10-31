//
//  ProtectedDataTests.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.10.26.
//

import XCTest
import UIKit
import KeyValueStorage

/// What SQLite and file storages do while the device is locked. Runs by hand, on a device with a passcode and
/// `KVS_LOCK_TEST=1` in the test environment: follow the `KVS-LOCK` prompts in the console.
final class ProtectedDataTests: XCTestCase {
    @MainActor
    func testWhatALockedDeviceDoes() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KVS_LOCK_TEST"] == "1", "Runs by hand on a device: set KVS_LOCK_TEST=1")
        #if targetEnvironment(simulator)
        throw XCTSkip("The Simulator never locks protected data")
        #else
        // Given: an open database of each protection class, and a file only readable while unlocked
        let report = Report()
        // The namespace's folder, with every protection level's database and the file in it
        let folder = try DefaultSQLiteLocator().databaseURL(for: .own(namespace: "ProtectedDataTests")).deletingLastPathComponent().deletingLastPathComponent()
        try? FileManager.default.removeItem(at: folder)
        defer { try? FileManager.default.removeItem(at: folder) }

        let protections: [SQLiteStorage.Protection] = [.whileLocked, .whileLockedUnlessOpen, .untilFirstUnlock, .none]
        func database(_ protection: SQLiteStorage.Protection) throws -> SQLiteStorage {
            try SQLiteStorage(scope: .own(protection: protection, namespace: "ProtectedDataTests"))
        }

        let databases = try protections.map { protection in
            let storage = try database(protection)
            try storage.save(Data([1]), forKey: "key")
            return (protection, storage)
        }

        let file = try FileStorage(scope: .own(protection: .whileLocked, namespace: "ProtectedDataTests"))
        try file.save(Data([1]), forKey: "key")

        // Keep running while locked, also without a debugger
        let task = UIApplication.shared.beginBackgroundTask(withName: "ProtectedDataTests")
        defer { UIApplication.shared.endBackgroundTask(task) }

        // When: the device locks, and its keys for protected data are dropped about 10 s later
        report.log("LOCK THE DEVICE NOW with the side button, and turn it face down so Face ID doesn't unlock it")
        await fulfillment(of: [XCTNSNotificationExpectation(name: UIApplication.protectedDataWillBecomeUnavailableNotification)], timeout: 120)
        report.log("Locked. Waiting 15 s for the keys to be dropped…")
        try await Task.sleep(nanoseconds: 15_000_000_000)

        // Then
        report.log("Protected data available: \(UIApplication.shared.isProtectedDataAvailable) (must be false for the results below to count)")
        for (protection, storage) in databases {
            report.result("SQLite \(protection), open connection, fetch") { try storage.fetch(forKey: "key") }
            report.result("SQLite \(protection), open connection, save") { try storage.save(Data([2]), forKey: "key") }
        }

        for protection in protections {
            report.result("SQLite \(protection), new connection, fetch") { try database(protection).fetch(forKey: "key") }
        }

        report.result("File .whileLocked, fetch") { try file.fetch(forKey: "key") }
        report.result("File .whileLocked, save") { try file.save(Data([2]), forKey: "key") }

        // When
        report.log("UNLOCK THE DEVICE NOW")
        await fulfillment(of: [XCTNSNotificationExpectation(name: UIApplication.protectedDataDidBecomeAvailableNotification)], timeout: 120)

        // Then: everything works again
        report.log("Protected data available: \(UIApplication.shared.isProtectedDataAvailable)")
        for (protection, storage) in databases {
            report.result("SQLite \(protection), after unlocking, fetch") { try storage.fetch(forKey: "key") }
        }

        report.result("File .whileLocked, after unlocking, fetch") { try file.fetch(forKey: "key") }
        report.log("Done. The report is also in the app's container: \(report.file.path)")
        #endif
    }
}

/// Prints each line with a `KVS-LOCK` prefix and keeps them all in `Documents/ProtectedDataReport.txt`,
/// in case the console disconnects while the device is locked.
private final class Report {
    let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ProtectedDataReport.txt")
    private var lines = [String]()

    func log(_ line: String) {
        print("KVS-LOCK \(line)")
        lines.append(line)
        try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    func result(_ label: String, _ body: () throws -> Any?) {
        do {
            log("\(label): ok, \(String(describing: try body()))")
        } catch {
            log("\(label): \(String(reflecting: error))")
        }
    }
}
