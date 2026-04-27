//
//  TestCase.swift
//  Auralis
//
//  Created by Daniel Bell on 5/16/25.
//

import Foundation

struct TestCase<T: Sendable>: Sendable {
    let json: String
    let expected: T
}
