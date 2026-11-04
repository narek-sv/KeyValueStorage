//
//  DataProtection.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 05.11.26.
//

import XCTest
import Foundation

/// Skips the test unless files in `folder` get their data protection class: a `.complete` probe doesn't on a locked
/// Mac, the iOS Simulator (no class) or GitHub's macOS runners (the default class).
func skipUnlessDataProtectionApplies(in folder: URL) throws {
    let probe = folder.appendingPathComponent("probe-\(UUID().uuidString)")
    try? Data([1]).write(to: probe, options: .completeFileProtection)
    let probeClass = try? FileManager.default.attributesOfItem(atPath: probe.path)[.protectionKey] as? FileProtectionType
    try? FileManager.default.removeItem(at: probe)
    try XCTSkipUnless(probeClass == .complete, "This volume doesn't apply data protection classes now")
}
