//
//  OptionalAdditions.swift
//
//
//  Created by Narek Sahakyan on 7/27/22.
//

import Foundation

extension Optional {
    func unwrapped(_ defaultValue: Wrapped) -> Wrapped {
        self ?? defaultValue
    }
}
