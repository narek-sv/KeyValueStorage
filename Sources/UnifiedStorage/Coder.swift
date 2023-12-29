//
//  Coder.swift
//  
//
//  Created by Narek Sahakyan on 11.12.23.
//

import Foundation

public protocol DataCoder: Sendable {
    func encode<Value: CodingValue>(_ value: Value) async throws -> Data
    func decode<Value: CodingValue>(_ data: Data) async throws -> Value
}

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
