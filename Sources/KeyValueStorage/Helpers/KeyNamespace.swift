//
//  KeyNamespace.swift
//  KeyValueStorage
//
//  Created by nsahakyan@servicetitan.com on 17.10.26.
//

/// Key prefixes of containers inside a shared store.
enum KeyNamespace {
    /// `<container>/`, with `%` and `/` percent-encoded, so containers never collide.
    static func prefix(for container: String) -> String {
        container
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "/", with: "%2F") + "/"
    }
}
