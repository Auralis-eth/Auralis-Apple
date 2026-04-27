//
//  GasPriceEstimate.swift
//  Auralis
//
//  Created by Daniel Bell on 8/25/25.
//

import SwiftUI

final class GasPriceEstimate: Codable, Sendable {
    let version: String
    let high: FeeDetails
    let networkCongestion: Double
    let historicalPriorityFeeRange: [String]
    let estimatedBaseFee: String
    let baseFeeTrend: String
    let latestPriorityFeeRange: [String]
    let medium: FeeDetails
    let priorityFeeTrend: String
    let low: FeeDetails
    let historicalBaseFeeRange: [String]

    struct FeeDetails: Codable, Sendable {
        let maxWaitTimeEstimate: Int
        let minWaitTimeEstimate: Int
        let suggestedMaxFeePerGas: String
        let suggestedMaxPriorityFeePerGas: String
    }

    init(version: String, high: FeeDetails, networkCongestion: Double, historicalPriorityFeeRange: [String], estimatedBaseFee: String, baseFeeTrend: String, latestPriorityFeeRange: [String], medium: FeeDetails, priorityFeeTrend: String, low: FeeDetails, historicalBaseFeeRange: [String]) {
        self.version = version
        self.high = high
        self.networkCongestion = networkCongestion
        self.historicalPriorityFeeRange = historicalPriorityFeeRange
        self.estimatedBaseFee = estimatedBaseFee
        self.baseFeeTrend = baseFeeTrend
        self.latestPriorityFeeRange = latestPriorityFeeRange
        self.medium = medium
        self.priorityFeeTrend = priorityFeeTrend
        self.low = low
        self.historicalBaseFeeRange = historicalBaseFeeRange
    }

    static var example: GasPriceEstimate {
        let low = FeeDetails(
            maxWaitTimeEstimate: 75_000,
            minWaitTimeEstimate: 45_000,
            suggestedMaxFeePerGas: "12.4",
            suggestedMaxPriorityFeePerGas: "0.35"
        )
        let medium = FeeDetails(
            maxWaitTimeEstimate: 45_000,
            minWaitTimeEstimate: 20_000,
            suggestedMaxFeePerGas: "18.9",
            suggestedMaxPriorityFeePerGas: "0.75"
        )
        let high = FeeDetails(
            maxWaitTimeEstimate: 20_000,
            minWaitTimeEstimate: 8_000,
            suggestedMaxFeePerGas: "26.7",
            suggestedMaxPriorityFeePerGas: "1.25"
        )

        return GasPriceEstimate(
            version: "2",
            high: high,
            networkCongestion: 0.42,
            historicalPriorityFeeRange: ["0.21", "1.37"],
            estimatedBaseFee: "11.8",
            baseFeeTrend: "down",
            latestPriorityFeeRange: ["0.35", "1.25"],
            medium: medium,
            priorityFeeTrend: "stable",
            low: low,
            historicalBaseFeeRange: ["9.4", "15.1"]
        )
    }
}
