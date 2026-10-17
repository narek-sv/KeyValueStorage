//
//  JSONDataCoder.swift
//  
//
//  Created by Narek Sahakyan on 31.12.23.
//

import Foundation

// MARK: - JSONDataCoder

public struct JSONDataCoder: DataCoder {
    // MARK: Properties

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    // MARK: Initializers

    public init(decoder: JSONDecoder = .init(), encoder: JSONEncoder = .init()) {
        self.decoder = decoder
        self.encoder = encoder
    }

    // MARK: Main Functionality

    public func encode<Value: CodingValue>(_ value: Value) throws -> Data {
        try encoder.encode(value)
    }
    
    public func decode<Value: CodingValue>(_ data: Data) throws -> Value {
        try decoder.decode(Value.self, from: data)
    }
}
