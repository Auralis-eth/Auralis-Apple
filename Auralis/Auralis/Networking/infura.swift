//
//  infura.swift
//  KickingHorse
//
//  Created by Daniel Bell on 10/9/24.
//

import SwiftUI
import AppIntents

@Observable
class GasPriceEstimate: Codable {
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

struct Infura {
    func getGasPrice() async -> GasPriceEstimate? {
        do {
            guard let apiKey = Secrets.apiKey(.infura) else {
                return nil
            }
            let chainId = 1
    //                        Supported networks
    //                        Arbitrum
    //                        Network    Chain ID
    //                        Mainnet    42161
    //                        Nova    42170

    //                        Base
    //                        Network    Chain ID
    //                        Mainnet    8453

    //                        Ethereum
    //                        Network    Chain ID
    //                        Mainnet    1
    //                        Holesky    17000
    //                        Sepolia    11155111

    //                        Filecoin
    //                        Network    Chain ID
    //                        Mainnet    314

    //                        Optimism
    //                        Network    Chain ID
    //                        Mainnet    10

    //                        Polygon
    //                        Network    Network ID
    //                        Mainnet    137
    //                        Amoy    80002

            let urlString = "https://gas.api.infura.io/v3/\(apiKey)/networks/\(chainId)/suggestedGasFees"

            guard let url = URL(string: urlString) else { return nil }
            let request = URLRequest(url: url)
            let response = try await URLSession.shared.data(for: request)

            do {
                let gas = try JSONDecoder().decode(GasPriceEstimate.self, from: response.0)
                return gas
            } catch {
                print(error)
            }
        } catch {
            print(error)
        }
        return nil
    }
}

