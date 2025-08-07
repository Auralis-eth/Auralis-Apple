//
//  RequestThrottler.swift
//  Auralis
//
//  Created by Daniel Bell on 8/6/25.
//

import Foundation

actor RequestThrottler {
    private var lastRequestTime: Date = .distantPast
    private let minimumInterval: TimeInterval = 0.1 // 100ms between requests

    func throttle() async {
        let now = Date()
        let timeElapsed = now.timeIntervalSince(lastRequestTime)

        if timeElapsed < minimumInterval {
            let delay = minimumInterval - timeElapsed
            try? await Task.sleep(nanoseconds: UInt64(delay * 100_000_000))
        }

        lastRequestTime = Date()
    }
}
