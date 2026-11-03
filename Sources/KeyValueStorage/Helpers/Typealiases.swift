//
//  Typealiases.swift
//  KeyValueStorage
//
//  Created by Narek Sahakyan on 29.12.23.
//

// MARK: - Typealiases

public typealias CodingValue = Codable & Sendable
/// A storage `UnifiedStorage` can share between tasks: any storage, synchronous or not, that is `Sendable`.
public typealias UnifiedStorable = AsyncDataStorage & Sendable
