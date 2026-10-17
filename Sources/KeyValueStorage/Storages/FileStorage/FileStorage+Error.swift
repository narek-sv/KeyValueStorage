//
//  FileStorage+Error.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 16.10.26.
//

// MARK: - FileStorage + Error

public extension FileStorage {  
  enum Error: KeyValueDataStorageError {
    case failedToFindGroupDirectory(String)
    case failedToFindDirectory(String)
    case invalidKey(String)
    case protectedDataUnavailable
    case other(Swift.Error)
  }
}
