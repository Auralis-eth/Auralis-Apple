//
//  GasPriceEstimate.swift
//  Auralis
//
//  Created by Daniel Bell on 8/25/25.
//

import SwiftUI

final class GasPriceEstimate: Codable {
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

    struct FeeDetails: Codable {
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
        let int1 = 420
        let string1 = "ethereum"
        let string2 = "solana"
        let double1: Double = 420.0
        let feeDetails = FeeDetails.init(maxWaitTimeEstimate: int1, minWaitTimeEstimate: int1, suggestedMaxFeePerGas: string1, suggestedMaxPriorityFeePerGas: string1)

        return GasPriceEstimate.init(version: string1, high: feeDetails, networkCongestion: double1, historicalPriorityFeeRange: [string1, string2], estimatedBaseFee: string1, baseFeeTrend: string1, latestPriorityFeeRange: [string1, string2], medium: feeDetails, priorityFeeTrend: string1, low: feeDetails, historicalBaseFeeRange: [string1, string2])
    }
}
