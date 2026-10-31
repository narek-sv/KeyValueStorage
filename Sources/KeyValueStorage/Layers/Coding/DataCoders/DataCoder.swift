//
//  DataCoder.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 31.12.23.
//

import Foundation

// MARK: - DataCoder

public protocol DataCoder: Sendable {
    func encode<Value: CodingValue>(_ value: Value) throws -> Data
    func decode<Value: CodingValue>(_ data: Data) throws -> Value
}

// MARK: - DataCoder + KeyValueCodingError

extension DataCoder {
    /// Encodes for both coding storages; the coder's failure is `.coding`.
    func encoded<Storage, Value: CodingValue>(_ value: Value, for _: Storage.Type) throws(KeyValueCodingError<Storage>) -> Data {
        do {
            return try encode(value)
        } catch {
            throw .coding(error)
        }
    }

    /// Decodes for both coding storages; the coder's failure is `.coding`.
    func decoded<Storage, Value: CodingValue>(_ data: Data, as _: Value.Type, for _: Storage.Type) throws(KeyValueCodingError<Storage>) -> Value {
        do {
            // Explicit, because the return type would otherwise make the coder decode `Value?`
            return try decode(data) as Value
        } catch {
            throw .coding(error)
        }
    }
}
