//
//  KeyNamespace.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 17.10.26.
//

import Foundation

// MARK: - KeyNamespace

/// Key prefixes of namespaces inside a shared store.
enum KeyNamespace {
    /// `<namespace>/`, with `%` and `/` percent-encoded, so namespaces never collide.
    static func prefix(for namespace: String) -> String {
        namespace
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "/", with: "%2F") + "/"
    }
}
