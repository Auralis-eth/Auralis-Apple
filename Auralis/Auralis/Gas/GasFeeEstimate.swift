//
//  GasFeeEstimate.swift
//  KickingHorse
//
//  Created by Daniel Bell on 10/1/24.
//

import SwiftUI

// MARK: - Formatted Display Data
struct FormattedGasPriceData {
    let historicalBaseFeeDisplay: String?
    let latestPriorityFeeDisplay: String?
    let historicalPriorityFeeDisplay: String?
    let showHistoricalBaseFee: Bool
    let showLatestPriorityFee: Bool
    let showHistoricalPriorityFee: Bool
    
    init?(estimate: GasPriceEstimate?) {
        guard let estimate else {
            return nil
        }
        self.showHistoricalBaseFee = !estimate.historicalBaseFeeRange.isEmpty
        self.showLatestPriorityFee = !estimate.latestPriorityFeeRange.isEmpty
        self.showHistoricalPriorityFee = !estimate.historicalPriorityFeeRange.isEmpty
        
        self.historicalBaseFeeDisplay = showHistoricalBaseFee ?
            estimate.historicalBaseFeeRange.joined(separator: " - ") : nil
        self.latestPriorityFeeDisplay = showLatestPriorityFee ?
            estimate.latestPriorityFeeRange.joined(separator: " - ") : nil
        self.historicalPriorityFeeDisplay = showHistoricalPriorityFee ?
            estimate.historicalPriorityFeeRange.joined(separator: " - ") : nil
    }
}

// MARK: - ViewModel
class GasPriceEstimateViewModel: ObservableObject {
    @Published private(set) var estimate: GasPriceEstimate?
    @Published private(set) var formattedData: FormattedGasPriceData?
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published private(set) var currentChain: Chain?
    
    private let service = Infura()
    private let debounceDelay: UInt64 = 500_000_000 // 0.5 seconds
    private var fetchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private let cacheValidityDuration: TimeInterval = 30 // 30 seconds
    
    deinit {
        cancelAllTasks()
    }
    
    func setChain(_ chain: Chain) {
        guard currentChain?.chainId != chain.chainId else { return }
        currentChain = chain
        error = nil // Clear previous errors when changing chains
        fetchGasPriceWithDebounce()
    }
    
    func fetchGasPrice() async {
        guard let chain = currentChain else { return }
        cancelAllTasks()
        fetchTask = Task {
            await performFetch(chainId: chain.chainId)
        }
    }
    
    func fetchGasPriceWithDebounce() {
        debounceTask?.cancel()
        
        debounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: debounceDelay)
                if !Task.isCancelled {
                    await fetchGasPrice()
                }
            } catch is CancellationError {
                // Task was cancelled, this is expected
            } catch {
                // Unexpected error in sleep
                self.error = error
            }
        }
    }
    
    func cancelAllTasks() {
        fetchTask?.cancel()
        debounceTask?.cancel()
        fetchTask = nil
        debounceTask = nil
    }
    
    @MainActor
    private func performFetch(chainId: Int) async {
        isLoading = true
        error = nil
        
        defer {
            isLoading = false
        }
        

        let result = await service.getGasPrice(chainId: chainId)
        
        if Task.isCancelled { return }
        
        self.estimate = result
        self.formattedData = FormattedGasPriceData(estimate: result)
        self.error = nil
    }
}

// MARK: - Main View
struct GasPriceEstimateView: View {
    @Binding var chain: Chain
    @StateObject private var viewModel = GasPriceEstimateViewModel()

    var body: some View {
        VStack(spacing: 12) {
            HeaderView()
            
            if viewModel.isLoading {
                LoadingView()
            } else if let estimate = viewModel.estimate,
                      let formattedData = viewModel.formattedData {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        FeeEstimateCardView(estimate: estimate)
                        BaseFeeCardView(estimate: estimate, formattedData: formattedData)
                        NetworkCongestionView(congestion: "\(estimate.networkCongestion)")
                        PriorityFeeCardView(estimate: estimate, formattedData: formattedData)
                    }
                    .padding(.horizontal)
                }
                .refreshable {
                    await viewModel.fetchGasPrice()
                }
            } else {
                ErrorView(error: viewModel.error, onRetry: viewModel.fetchGasPrice)
            }
        }
        .padding()
        .task {
            viewModel.setChain(chain)
            await viewModel.fetchGasPrice()
        }
        .onChange(of: chain) { newChain, oldchain in
            viewModel.setChain(newChain)
        }
        .onDisappear {
            viewModel.cancelAllTasks()
        }
    }
}

extension GasPriceEstimateView {
    // MARK: - Header View
    struct HeaderView: View {
        var body: some View {
            HStack {
                HeadlineFontText("Ethereum Gas Tracker")
                
                Spacer()
                
                AccentTextSystemImage("fuelpump")
                    .accessibilityLabel("Ethereum gas tracker icon")
                    .accessibilityAddTraits(.isImage)
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
            .padding()
            .glassEffect(.regular.tint(.surface), in: .rect(cornerRadius: 30, style: .continuous))
        }
    }

    // MARK: - Error View
    struct ErrorView: View {
        let error: Error?
        let onRetry: () async -> Void
        
        var body: some View {
            ContentUnavailableView {
                Label("Gas Price Data Unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.error)
            } description: {
                SecondaryText(error?.localizedDescription ?? "Failed to fetch gas price estimate. Please try again later.")
            } actions: {
                PrimaryTextButton("Try Again") {
                    Task {
                        await onRetry()
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200)
            .padding()
            .glassEffect(.regular.tint(.surface), in: .rect(cornerRadius: 30, style: .continuous))
        }
    }

    // MARK: - Fee Estimate Card
    struct FeeEstimateCardView: View {
        let estimate: GasPriceEstimate

        var body: some View {
            VStack(spacing: 12) {
                SubheadlineFontText("Gas Fee Estimates")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider().background(Color.textSecondary.opacity(0.3))

                GasFeeEstimateRow(title: "Safe", estimate: estimate.low)
                GasFeeEstimateRow(title: "Average", estimate: estimate.medium)
                GasFeeEstimateRow(title: "Fast", estimate: estimate.high)
            }
            .padding()
            .glassEffect(.regular.tint(.surface), in: .rect(cornerRadius: 30, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Gas fee estimates")
        }
    }

    // MARK: - Base Fee Card
    struct BaseFeeCardView: View {
        let estimate: GasPriceEstimate
        let formattedData: FormattedGasPriceData

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                SubheadlineFontText("Base Fee Information")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider().background(Color.textSecondary.opacity(0.3))

                DataRowView(
                    title: "Estimated Base Fee",
                    value: estimate.estimatedBaseFee,
                    isTrendUp: estimate.baseFeeTrend != "down"
                )

                if formattedData.showHistoricalBaseFee,
                   let historicalDisplay = formattedData.historicalBaseFeeDisplay {
                    DataRowView(
                        title: "Historical Base Fee Range",
                        value: historicalDisplay,
                        isTrendUp: estimate.baseFeeTrend != "down"
                    )
                }
            }
            .padding()
            .glassEffect(.regular.tint(.surface), in: .rect(cornerRadius: 30, style: .continuous))
        }
    }

    // MARK: - Priority Fee Card
    struct PriorityFeeCardView: View {
        let estimate: GasPriceEstimate
        let formattedData: FormattedGasPriceData

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                SubheadlineFontText("Priority Fee Information")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider().background(Color.textSecondary.opacity(0.3))

                if formattedData.showLatestPriorityFee,
                   let latestDisplay = formattedData.latestPriorityFeeDisplay {
                    DataRowView(
                        title: "Latest Priority Fee Range",
                        value: latestDisplay,
                        isTrendUp: estimate.priorityFeeTrend != "down"
                    )
                }

                if formattedData.showHistoricalPriorityFee,
                   let historicalDisplay = formattedData.historicalPriorityFeeDisplay {
                    DataRowView(
                        title: "Historical Priority Fee Range",
                        value: historicalDisplay,
                        isTrendUp: estimate.priorityFeeTrend != "down"
                    )
                }
            }
            .padding()
            .glassEffect(.regular.tint(.surface), in: .rect(cornerRadius: 30, style: .continuous))
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
            .padding()
            .glassEffect(.regular.tint(.surface), in: .rect(cornerRadius: 30, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Network congestion")
            .accessibilityValue(congestion)
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

    enum CongestionLevel {
        case low, medium, high
    }
    
    // MARK: - Congestion Indicator
    struct CongestionIndicator: View {
        let level: CongestionLevel

        var body: some View {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(getColor(for: index))
                        .frame(width: 8, height: CGFloat(index * 3) + 8)
                }
            }
        }
        
        private var activeBars: Int {
            switch level {
            case .low: return 1
            case .medium: return 2
            case .high: return 3
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title) fee: \(estimate.suggestedMaxPriorityFeePerGas)")
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
                        .foregroundStyle(isTrendUp ? Color.success : .error)
                }

                SecondaryText(value)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
        }
    }
}


