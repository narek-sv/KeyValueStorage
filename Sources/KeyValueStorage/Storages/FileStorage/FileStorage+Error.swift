//
//  FileStorage+Error.swift
//  KeyValueStorage
//
//  Created by nsahakyan@servicetitan.com on 16.10.26.
//

import Foundation

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
