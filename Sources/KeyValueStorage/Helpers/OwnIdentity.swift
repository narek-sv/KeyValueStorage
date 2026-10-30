//
//  OwnIdentity.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 30.10.26.
//

import Foundation

// MARK: - OwnIdentity

/// The identifiers of the running app or extension, which the `.own` scopes belong to.
public enum OwnIdentity {
    /// `Bundle.main.bundleIdentifier`.
    public static var bundleIdentifier: String? {
        Bundle.main.bundleIdentifier
    }

    /// `ProcessInfo.processInfo.processName`, the process's identifier where there's no bundle ID.
    public static var processName: String {
        ProcessInfo.processInfo.processName
    }
    
    /// `bundleIdentifier`, or `processName` where there's no bundle ID.
    public static var identifier: String {
        bundleIdentifier ?? processName
    }
}
