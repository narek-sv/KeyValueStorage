//
//  RawDataCoder.swift
//
//
//  Created by Narek Sahakyan on 15.10.26.
//

import Foundation

// MARK: - RawDataCoder

/// Stores `Data` as is and `String` as UTF-8, and encodes every other type with the fallback coder.
///
/// Raw bytes skip encoding, which makes large values much faster and smaller than base64 or quoted text,
/// and lets keys read raw values saved by other code, such as an existing token in the keychain.
/// Other types go through the fallback, which detects most values that were saved as a different type.
public struct RawDataCoder: DataCoder {
    // MARK: Properties

    private let fallback: DataCoder
    
    // MARK: Initializers

    public init(fallback: DataCoder = JSONDataCoder()) {
        self.fallback = fallback
    }
    
    // MARK: Main Functionality
    
    // Types are compared exactly, so wrapped types such as `Data?` or `[String]` go to the fallback
    
    public func encode<Value: CodingValue>(_ value: Value) async throws -> Data {
        if Value.self == Data.self, let data = value as? Data {
            return data
        }
        
        if Value.self == String.self, let string = value as? String {
            return Data(string.utf8)
        }
        
        return try await fallback.encode(value)
    }
    
    public func decode<Value: CodingValue>(_ data: Data) async throws -> Value {
        if Value.self == Data.self, let value = data as? Value {
            return value
        }
        
        if Value.self == String.self {
            guard let string = String(data: data, encoding: .utf8), let value = string as? Value else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "The data isn't valid UTF-8"))
            }
            
            return value
        }
        
        return try await fallback.decode(data)
    }
}
