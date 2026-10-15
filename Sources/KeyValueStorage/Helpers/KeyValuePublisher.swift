//
//  KeyValuePublisher.swift
//
//
//  Created by Narek Sahakyan on 15.10.26.
//

import Combine

/// Publishes the changes of a stored value, and can be passed between concurrency domains.
///
/// Combine's type-erased publishers aren't marked `Sendable`, so they can't be returned from the storage actors.
/// Subscribing to and cancelling Combine subscriptions is thread-safe, which makes sharing this wrapper safe.
public struct KeyValuePublisher<Output: Sendable>: Publisher, @unchecked Sendable {
    public typealias Failure = Never

    private let upstream: AnyPublisher<Output, Never>

    init(_ upstream: AnyPublisher<Output, Never>) {
        self.upstream = upstream
    }

    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Never {
        upstream.receive(subscriber: subscriber)
    }
}
