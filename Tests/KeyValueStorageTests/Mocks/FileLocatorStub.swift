//
//  FileLocatorStub.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 28.10.26.
//

import Foundation
@testable import KeyValueStorage

/// Fixed names, to check that the storage uses exactly what its locator returns; records each call.
final class FileLocatorStub: FileLocator {
    enum Call: Equatable {
        case directory(FileStorage.Scope)
        case fileName(FileStorage.Key, FileStorage.Scope)
        case key(String, FileStorage.Scope)
    }

    private(set) var calls = [Call]()
    var directory = URL(fileURLWithPath: "/located", isDirectory: true)
    var directoryError: FileStorage.Error?
    var fileNameError: FileStorage.Error?
    /// The file names the locator claims, and their keys.
    var keys = [String: FileStorage.Key]()

    func directory(for scope: FileStorage.Scope) throws(FileStorage.Error) -> URL {
        calls.append(.directory(scope))
        if let directoryError {
            throw directoryError
        }

        return directory
    }

    func fileName(forKey key: FileStorage.Key, in scope: FileStorage.Scope) throws(FileStorage.Error) -> String {
        calls.append(.fileName(key, scope))
        if let fileNameError {
            throw fileNameError
        }

        return "located-\(key)"
    }

    func key(forFileName fileName: String, in scope: FileStorage.Scope) -> FileStorage.Key? {
        calls.append(.key(fileName, scope))
        return keys[fileName]
    }
}
