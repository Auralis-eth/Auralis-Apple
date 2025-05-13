//
//  GasFeeEstimate.swift
//  KickingHorse
//
//  Created by Daniel Bell on 10/1/24.
//

import SwiftUI

// MARK: - Main View
struct GasPriceEstimateView: View {
    @Binding var chain: Chain
    @State private var estimate: GasPriceEstimate?
    @State private var isLoading = false
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HeaderView()

                if let estimate = estimate {
                    ScrollView {
                        VStack(spacing: 16) {
                            FeeEstimateCardView(estimate: estimate)
                            BaseFeeCardView(estimate: estimate)

                            NetworkCongestionView(congestion: "\(estimate.networkCongestion)")
                                .padding(.horizontal)

                            PriorityFeeCardView(estimate: estimate)
                        }
                    }
                } else {
                    if isLoading {
                        LoadingView()
                    } else {
                        ErrorView()
                    }
                }
            }
            .padding()
            .background(Color.surface)
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 3)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.deepBlue.opacity(0.2), lineWidth: 1)
            )
            .background(Color.background)
            .task {
                await fetchGasPrice()
            }
            .onChange(of: chain) { newValue in
                Task {
                    await fetchGasPrice()
                }
            }
        }
    }

    func fetchGasPrice() async {
        isLoading = true

        let result = await Infura().getGasPrice(chainId: chain.chainId)

        await MainActor.run {
            self.estimate = result
            self.isLoading = false
        }
    }
}

extension GasPriceEstimateView {
    // MARK: - Header View
    struct HeaderView: View {
        var body: some View {
            HStack {
                HeadlineFontText("Ethereum Gas Tracker")

                AccentTextSystemImage( "fuelpump")
            }
            .padding(.top, 8)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Loading View
    struct LoadingView: View {
        var body: some View {
            VStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .accent))
                    .scaleEffect(1.2)
                    .padding()

                SecondaryText("Fetching gas prices...")
            }
            .frame(maxWidth: .infinity, minHeight: 200)
            .background(Color.surface)
            .cornerRadius(10)
        }
    }

    // MARK: - Error View
    struct ErrorView: View {
        var body: some View {
            ContentUnavailableView {
                Label("Gas Price Data Unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.error)
            } description: {
                SecondaryText("Failed to fetch gas price estimate. Please try again later.")
            } actions: {
                PrimaryTextButton("Try Again") {
                    // Reconnect action would go here
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    // MARK: - Card View Wrapper
    struct CardView<Content: View>: View {
        let content: Content

        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        var body: some View {
            content
                .padding()
                .background(Color.surface)
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.deepBlue.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)
        }
    }

    // MARK: - Fee Estimate Card
    struct FeeEstimateCardView: View {
        let estimate: GasPriceEstimate

        var body: some View {
            CardView {
                VStack(spacing: 12) {
                    SubheadlineFontText("Gas Fee Estimates")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().background(Color.textSecondary.opacity(0.3))

                    GasFeeEstimateRow(title: "Safe", estimate: estimate.low)
                    GasFeeEstimateRow(title: "Average", estimate: estimate.medium)
                    GasFeeEstimateRow(title: "Fast", estimate: estimate.high)
                }
            }
        }
    }

    // MARK: - Base Fee Card
    struct BaseFeeCardView: View {
        let estimate: GasPriceEstimate

        var body: some View {
            CardView {
                VStack(alignment: .leading, spacing: 12) {
                    SubheadlineFontText("Base Fee Information")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().background(Color.textSecondary.opacity(0.3))

                    DataRowView(
                        title: "Estimated Base Fee",
                        value: estimate.estimatedBaseFee,
                        isTrendUp: estimate.baseFeeTrend != "down"
                    )

                    DataRowView(
                        title: "Historical Base Fee Range",
                        value: estimate.historicalBaseFeeRange.joined(separator: " - "),
                        isTrendUp: estimate.baseFeeTrend != "down"
                    )
                }
            }
        }
    }

    // MARK: - Priority Fee Card
    struct PriorityFeeCardView: View {
        let estimate: GasPriceEstimate

        var body: some View {
            CardView {
                VStack(alignment: .leading, spacing: 12) {
                    SubheadlineFontText("Priority Fee Information")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().background(Color.textSecondary.opacity(0.3))

                    DataRowView(
                        title: "Latest Priority Fee Range",
                        value: estimate.latestPriorityFeeRange.joined(separator: " - "),
                        isTrendUp: estimate.priorityFeeTrend != "down"
                    )

                    DataRowView(
                        title: "Historical Priority Fee Range",
                        value: estimate.historicalPriorityFeeRange.joined(separator: " - "),
                        isTrendUp: estimate.priorityFeeTrend != "down"
                    )
                }
            }
        }
    }

    // MARK: - Network Congestion View
    struct NetworkCongestionView: View {
        let congestion: String

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                SubheadlineFontText("Network Congestion")

                HStack {
                    HeadlineFontText(congestion)

                    Spacer()

                    CongestionIndicator(level: congestionLevel)
                }
            }
        }

        private var congestionLevel: CongestionLevel {
            let lowercasedCongestion = congestion.lowercased()
            if lowercasedCongestion.contains("high") {
                return .high
            } else if lowercasedCongestion.contains("medium") {
                return .medium
            } else {
                return .low
            }
        }
    }

    // MARK: - Congestion Indicator
    enum CongestionLevel {
        case low, medium, high
    }

    struct CongestionIndicator: View {
        let level: CongestionLevel

        var body: some View {
            HStack(spacing: 2) {
                ForEach(0..<3) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(getColor(for: index))
                        .frame(width: 8, height: CGFloat(index * 3) + 8)
                }
            }
        }

        private func getColor(for index: Int) -> Color {
            switch level {
                case .low:
                    return index == 0 ? .success : .textSecondary.opacity(0.3)
                case .medium:
                    return index <= 1 ? .secondary : .textSecondary.opacity(0.3)
                case .high:
                    return index <= 2 ? .error : .textSecondary.opacity(0.3)
            }
        }
    }

    // MARK: - Fee Estimate Row
    struct GasFeeEstimateRow: View {
        var title: String
        var estimate: GasPriceEstimate.FeeDetails

        var body: some View {
            HStack {
                PrimaryText(title)

                Spacer()

                PrimaryText(estimate.suggestedMaxPriorityFeePerGas)
                    .fontWeight(.medium)
            }
        }
    }

    // MARK: - Data Row View
    struct DataRowView: View {
        let title: String
        let value: String
        let isTrendUp: Bool

        var accessibilityLabel: String {
            "\(title): \(value) trending \(isTrendUp ? "up" : "down")"
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    PrimaryText(title)
                        .fontWeight(.semibold)

                    Spacer()

                    SystemImage(isTrendUp ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundColor(isTrendUp ? .success : .error)
                }

                SecondaryText(value)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
        }
    }
}
