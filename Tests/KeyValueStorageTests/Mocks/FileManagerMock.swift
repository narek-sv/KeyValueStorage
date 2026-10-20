//
//  FileManagerMock.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 26.02.24.
//

import Foundation

final class FileManagerMock: FileManager {
    var storage = [String: Data]()
    var removeItemError: CocoaError?
    var createDirectoryError: CocoaError?
    
    override func removeItem(atPath path: String) throws {
        if let removeItemError {
            throw removeItemError
        }
        
        storage[path] = nil
    }
    
    override func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = nil) throws {
        if let createDirectoryError {
            throw createDirectoryError
        }
    }
}
