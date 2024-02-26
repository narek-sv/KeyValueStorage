//
//  FileManagerMock.swift
//
//
//  Created by Narek Sahakyan on 26.02.24.
//

import Foundation

final class FileManagerMock: FileManager {
    var removeItemError: CocoaError?
    var createDirectoryError: CocoaError?
    var createFileError: CocoaError?
    
    override func removeItem(atPath path: String) throws {
        if let removeItemError {
            throw removeItemError
        }
    }
    
    override func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = nil) throws {
        if let createDirectoryError {
            throw createDirectoryError
        }
    }
    
    override func createFile(atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey : Any]? = nil) -> Bool {
        createFileError == nil
    }
}
