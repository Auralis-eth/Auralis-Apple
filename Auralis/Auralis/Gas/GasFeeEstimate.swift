//
//  GasFeeEstimate.swift
//  KickingHorse
//
//  Created by Daniel Bell on 10/1/24.
//

import SwiftUI

struct GasFeeEstimateCard: View {
    var title: String
    var estimate: GasPriceEstimate.FeeDetails

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(estimate.suggestedMaxPriorityFeePerGas)
        }
    }
}
struct GasPriceEstimateDataRow: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .fontWeight(.semibold)
            Text(value)
        }
    }
}
struct GasPriceEstimateView: View {
    @State var estimate: GasPriceEstimate?
    var body: some View {
        VStack {
            HStack {
                Text("Ethereum Gas Tracker")
                    .font(.headline)
                Image(systemName: "fuelpump")
                    .foregroundStyle(Color.purple)
            }
            if let estimate {
                VStack(spacing: 4) {
                    VStack {
                        Text("Ethereum Gas Tracker")
                            .font(.subheadline)
                        GasFeeEstimateCard(title: "Safe", estimate: estimate.low)
                        GasFeeEstimateCard(title: "Average", estimate: estimate.medium)
                        GasFeeEstimateCard(title: "Fast", estimate: estimate.high)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(color: Color.gray.opacity(0.4), radius: 5, x: 0, y: 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray, lineWidth: 1)
                    )
                    .padding()
                    VStack {
                        GasPriceEstimateDataRow(title: "Estimated Base Fee", value: estimate.estimatedBaseFee)
                        GasPriceEstimateDataRow(title: "Historical Base Fee Range", value: "\(estimate.historicalBaseFeeRange.joined(separator: " - "))")
                    }
                    .foregroundStyle(estimate.baseFeeTrend == "down" ? .red : .green)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(color: Color.gray.opacity(0.4), radius: 5, x: 0, y: 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray, lineWidth: 1)
                    )
                    .padding()
                    Divider()
                    GasPriceEstimateDataRow(title: "Network Congestion", value: "\(estimate.networkCongestion)")
                    Divider()
                    VStack {
                        GasPriceEstimateDataRow(title: "Latest Priority Fee Range", value: "\(estimate.latestPriorityFeeRange.joined(separator: " - "))")
                        GasPriceEstimateDataRow(title: "Historical Priority Fee Range", value: "\(estimate.historicalPriorityFeeRange.joined(separator: " - "))")
                    }
                    .foregroundStyle(estimate.priorityFeeTrend == "down" ? .red : .green)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(color: Color.gray.opacity(0.4), radius: 5, x: 0, y: 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray, lineWidth: 1)
                    )
                    .padding()



                }
            } else {
                ContentUnavailableView("Failed to fetch gas price estimate.", image: "gas-pump.fill")
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: Color.gray.opacity(0.4), radius: 5, x: 0, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray, lineWidth: 1)
        )
        .padding()
        .task {
            self.estimate = await Infura().getGasPrice()
        }
    }
}

