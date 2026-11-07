//
//  KeychainHostApp.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 15.10.26.
//

import SwiftUI

/// Hosts the keychain tests, because only an app can have the keychain entitlements they need.
@main
struct KeychainHostApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Hosts the KeyValueStorage keychain tests")
        }
    }
}
