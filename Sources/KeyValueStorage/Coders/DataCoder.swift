//
//  DataCoder.swift
//
//
//  Created by Narek Sahakyan on 31.12.23.
//

import Foundation

public protocol DataCoder: Sendable {
    func encode<Value: CodingValue>(_ value: Value) async throws -> Data
    func decode<Value: CodingValue>(_ data: Data) async throws -> Value
}
