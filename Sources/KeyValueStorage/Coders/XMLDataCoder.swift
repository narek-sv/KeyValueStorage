//
//  XMLDataCoder.swift
//
//
//  Created by Narek Sahakyan on 31.12.23.
//

import Foundation

public actor XMLDataCoder: DataCoder {
    private let decoder: PropertyListDecoder
    private let encoder: PropertyListEncoder
    
    public init(decoder: PropertyListDecoder = .init(), encoder: PropertyListEncoder = .init()) {
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
