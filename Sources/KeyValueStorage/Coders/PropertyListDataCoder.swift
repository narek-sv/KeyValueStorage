//
//  PropertyListDataCoder.swift
//
//
//  Created by Narek Sahakyan on 31.12.23.
//

import Foundation

/// Encodes values as property lists, in the binary format unless the given encoder sets another `outputFormat`.
public actor PropertyListDataCoder: DataCoder {
    private let decoder: PropertyListDecoder
    private let encoder: PropertyListEncoder
    
    public init(decoder: PropertyListDecoder = .init(), encoder: PropertyListEncoder = .init()) {
        self.decoder = decoder
        self.encoder = encoder
    }

    /// A property list can't have a single value, such as a string or a number, at its root,
    /// so every value is stored as the only element of an array.
    public func encode<Value: CodingValue>(_ value: Value) throws -> Data {
        try encoder.encode([value])
    }
    
    public func decode<Value: CodingValue>(_ data: Data) throws -> Value {
        let values = try decoder.decode([Value].self, from: data)
        guard values.count == 1, let value = values.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected exactly one value, found \(values.count)"))
        }
        
        return value
    }
}
