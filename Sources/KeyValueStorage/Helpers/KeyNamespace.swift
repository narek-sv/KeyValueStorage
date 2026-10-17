//
//  KeyNamespace.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import Foundation

// MARK: - KeyNamespace

/// Key prefixes of containers inside a shared store.
enum KeyNamespace {
    /// `<container>/`, with `%` and `/` percent-encoded, so containers never collide.
    static func prefix(for container: String) -> String {
        container
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "/", with: "%2F") + "/"
    }
}
