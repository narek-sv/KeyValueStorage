//
//  SendableConformances.swift
//
//
//  Created by Narek Sahakyan on 31.12.23.
//

import Foundation
import Combine

extension UserDefaults: @unchecked Sendable { }
extension AnyPublisher: @unchecked Sendable { }

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension AsyncPublisher: @unchecked Sendable { }
