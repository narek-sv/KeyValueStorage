//
//  JSONDataCoder.swift
//  
//
//  Created by Narek Sahakyan on 31.12.23.
//

import Foundation

public actor JSONDataCoder: DataCoder {
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    public init(decoder: JSONDecoder = .init(), encoder: JSONEncoder = .init()) {
        self.decoder = decoder
        self.encoder = encoder
    }

    public func encode<Value: CodingValue>(_ value: Value) throws -> Data {
        try encoder.encode(value)
    }
    
    public func decode<Value: CodingValue>(_ data: Data) throws -> Value {
        try decoder.decode(Value.self, from: data)
    }
}
