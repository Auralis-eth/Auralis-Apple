//
//  GasFeeEstimate.swift
//  KickingHorse
//
//  Created by Daniel Bell on 10/1/24.
//

import SwiftUI

// MARK: - Enums for Type Safety
enum UrgencyLevel: String, CaseIterable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: return "Safe"
        case .medium: return "Standard"
        case .high: return "Fast"
        }
    }

    var description: String {
        switch self {
        case .low: return "Cheapest option, may take longer"
        case .medium: return "Balanced speed and cost"
        case .high: return "Fastest confirmation, higher cost"
        }
    }
}

enum CongestionLevel: String, CaseIterable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

enum TrendDirection {
    case up, down, stable

    var isUp: Bool { self == .up }

    var icon: String {
        switch self {
        case .up: return "arrow.up.circle.fill"
        case .down: return "arrow.down.circle.fill"
        case .stable: return "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .up: return .red // Up trend = more expensive = bad for users
        case .down: return .green // Down trend = cheaper = good for users
        case .stable: return .gray
        }
    }
}

// MARK: - Extensions for Business Logic
extension GasPriceEstimate {
    // Convert networkCongestion (0-1) to congestion level
    var congestionLevel: CongestionLevel {
        if networkCongestion >= 0.7 { return .high }
        if networkCongestion >= 0.3 { return .medium }
        return .low
    }

    var baseFeeTrendDirection: TrendDirection {
        switch baseFeeTrend.lowercased() {
        case "up": return .up
        case "down": return .down
        default: return .stable
        }
    }

    var priorityFeeTrendDirection: TrendDirection {
        switch priorityFeeTrend.lowercased() {
        case "up": return .up
        case "down": return .down
        default: return .stable
        }
    }

    // Display properties with proper units
    var networkCongestionDisplay: String {
        String(format: "%.1f%%", networkCongestion * 100)
    }

    var estimatedBaseFeeDisplay: String {
        formatGweiValue(estimatedBaseFee)
    }

    var historicalBaseFeeDisplay: String {
        guard historicalBaseFeeRange.count >= 2 else { return "N/A" }
        return "\(formatGweiValue(historicalBaseFeeRange[0])) - \(formatGweiValue(historicalBaseFeeRange[1]))"
    }

    var latestPriorityFeeDisplay: String {
        guard latestPriorityFeeRange.count >= 2 else { return "N/A" }
        return "\(formatGweiValue(latestPriorityFeeRange[0])) - \(formatGweiValue(latestPriorityFeeRange[1]))"
    }

    var historicalPriorityFeeDisplay: String {
        guard historicalPriorityFeeRange.count >= 2 else { return "N/A" }
        return "\(formatGweiValue(historicalPriorityFeeRange[0])) - \(formatGweiValue(historicalPriorityFeeRange[1]))"
    }

    private func formatGweiValue(_ value: String) -> String {
        guard let doubleValue = Double(value) else { return value }
        if doubleValue < 0.001 {
            return String(format: "%.6f Gwei", doubleValue)
        } else if doubleValue < 1 {
            return String(format: "%.3f Gwei", doubleValue)
        } else {
            return String(format: "%.1f Gwei", doubleValue)
        }
    }
}

extension GasPriceEstimate.FeeDetails {
    var maxFeeDisplay: String {
        guard let doubleValue = Double(suggestedMaxFeePerGas) else { return suggestedMaxFeePerGas }
        return String(format: "%.1f Gwei", doubleValue)
    }

    var priorityFeeDisplay: String {
        guard let doubleValue = Double(suggestedMaxPriorityFeePerGas) else { return suggestedMaxPriorityFeePerGas }
        return String(format: "%.3f Gwei", doubleValue)
    }

    var waitTimeDisplay: String {
        let minSeconds = minWaitTimeEstimate / 1000
        let maxSeconds = maxWaitTimeEstimate / 1000

        if maxSeconds < 60 {
            return "\(minSeconds)-\(maxSeconds)s"
        } else {
            let minMinutes = minSeconds / 60
            let maxMinutes = maxSeconds / 60
            return "\(minMinutes)-\(maxMinutes)m"
        }
    }
}

// MARK: - ViewModel
@MainActor
final class GasPriceEstimateViewModel: ObservableObject {
    @Published private(set) var estimate: GasPriceEstimate?
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published private(set) var currentChain: Chain?
    @Published private(set) var lastUpdated: Date?

    private let provider: any GasPricingProviding
    private var currentTask: Task<Void, Never>?
    private var refreshTimer: Timer?

    init(provider: any GasPricingProviding = AlchemyGasPricingProvider()) {
        self.provider = provider
    }

    deinit {
        currentTask?.cancel()
        refreshTimer?.invalidate()
    }

    func setChain(_ chain: Chain) {
        guard currentChain?.chainId != chain.chainId else { return }

        // Clear stale data immediately when changing chains
        if currentChain != nil {
            estimate = nil
            error = nil
            lastUpdated = nil
        }

        currentChain = chain

        // Cancel any existing fetch
        currentTask?.cancel()
        refreshTimer?.invalidate()

        // Start new fetch with slight debounce for chain changes
        currentTask = Task {
            defer { currentTask = nil }
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled {
                await performFetch(for: chain)
                startAutoRefresh()
            }
        }
    }

    func fetchGasPrice() async {
        guard let chain = currentChain else { return }
        await performFetch(for: chain)
    }

    private func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.handleAutoRefreshTick()
            }
        }
    }

    private func handleAutoRefreshTick() async {
        guard !isLoading else { return }
        await fetchGasPrice()
    }

    private func performFetch(for chain: Chain) async {
        isLoading = true
        error = nil

        defer {
            isLoading = false
        }

        do {
            let result = try await provider.gasPriceEstimate(for: chain)

            // Only update if we're still on the same chain and not cancelled
            if !Task.isCancelled && currentChain?.chainId == chain.chainId {
                self.estimate = result
                self.error = nil
                self.lastUpdated = Date()
            }
        } catch {
            if !Task.isCancelled && currentChain?.chainId == chain.chainId {
                self.estimate = nil
                self.error = error
            }
        }
    }
}

// MARK: - Main View
struct GasPriceEstimateView: View {
    @Binding var chain: Chain
    @StateObject private var viewModel = GasPriceEstimateViewModel()

    var body: some View {
        VStack(spacing: 12) {
            HeaderView(
                chainName: chain.networkName,
                lastUpdated: viewModel.lastUpdated,
                isLoading: viewModel.isLoading
            )

            content
        }
        .padding()
        .task(id: chain.chainId) {
            viewModel.setChain(chain)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let estimate = viewModel.estimate {
            ScrollView {
                LazyVStack(spacing: 16) {
                    FeeEstimateCardView(estimate: estimate)

                    HStack(spacing: 12) {
                        BaseFeeCardView(estimate: estimate)
                        NetworkCongestionView(estimate: estimate)
                    }

                    PriorityFeeCardView(estimate: estimate)
                }
                .padding(.horizontal)
            }
            .refreshable {
                await viewModel.fetchGasPrice()
            }
        } else if viewModel.isLoading {
            LoadingView()
        } else {
            ErrorView(
                error: viewModel.error,
                onRetry: {
                    await viewModel.fetchGasPrice()
                }
            )
        }
    }
}

extension GasPriceEstimateView {
    // MARK: - Header View
    struct HeaderView: View {
        let chainName: String
        let lastUpdated: Date?
        let isLoading: Bool

        var body: some View {
            VStack(spacing: 8) {
                AuraSectionHeader(
                    title: "\(chainName) Gas Tracker",
                    subtitle: lastUpdatedText
                ) {
                    AuraPill(
                        isLoading ? "Updating" : "Live",
                        systemImage: isLoading ? "arrow.triangle.2.circlepath" : "fuelpump",
                        emphasis: isLoading ? .neutral : .accent
                    )
                }
            }
            .padding(.top, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(chainName) gas tracker")
            .accessibilityValue(accessibilityValue)
        }

        private var lastUpdatedText: String? {
            guard let lastUpdated else { return nil }
            return "Last updated: \(lastUpdated.formatted(.dateTime.hour().minute()))"
        }

        private var accessibilityValue: String {
            if let lastUpdatedText {
                return "\(isLoading ? "Updating" : "Live"). \(lastUpdatedText)"
            }

            return isLoading ? "Updating" : "Live"
        }
    }

    // MARK: - Loading View
    struct LoadingView: View {
        var body: some View {
            AuraSurfaceCard {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .tint(.accent)
                        .scaleEffect(1.2)

                    SecondaryText("Fetching gas prices...")
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Error View
    struct ErrorView: View {
        let error: Error?
        let onRetry: () async -> Void

        var body: some View {
            AuraSurfaceCard {
                ContentUnavailableView {
                    Label("Gas Price Data Unavailable", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.error)
                } description: {
                    SecondaryText(errorMessage)
                } actions: {
                    AuraActionButton("Try Again", systemImage: "arrow.clockwise") {
                        Task {
                            await onRetry()
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }

        private var errorMessage: String {
            guard let error = error else {
                return "Failed to fetch gas price estimate. Please try again later."
            }
            return error.localizedDescription
        }
    }

    // MARK: - Reusable Card Component
    struct CardView<Content: View>: View {
        let title: String
        let content: () -> Content

        init(title: String, @ViewBuilder content: @escaping () -> Content) {
            self.title = title
            self.content = content
        }

        var body: some View {
            AuraSurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    AuraSectionHeader(title: title)

                    Divider()
                        .background(Color.textSecondary.opacity(0.3))

                    content()
                }
            }
        }
    }

    // MARK: - Fee Estimate Card
    struct FeeEstimateCardView: View {
        let estimate: GasPriceEstimate

        var body: some View {
            CardView(title: "Gas Fee Estimates") {
                VStack(spacing: 12) {
                    GasFeeEstimateRow(
                        urgency: .low,
                        feeDetails: estimate.low
                    )
                    GasFeeEstimateRow(
                        urgency: .medium,
                        feeDetails: estimate.medium
                    )
                    GasFeeEstimateRow(
                        urgency: .high,
                        feeDetails: estimate.high
                    )
                }
            }
        }
    }

    // MARK: - Base Fee Card
    struct BaseFeeCardView: View {
        let estimate: GasPriceEstimate

        var body: some View {
            CardView(title: "Base Fee") {
                VStack(spacing: 12) {
                    DataRowView(
                        title: "Current",
                        value: estimate.estimatedBaseFeeDisplay,
                        trend: estimate.baseFeeTrendDirection
                    )

                    DataRowView(
                        title: "24h Range",
                        value: estimate.historicalBaseFeeDisplay,
                        trend: nil
                    )
                }
            }
        }
    }

    // MARK: - Priority Fee Card
    struct PriorityFeeCardView: View {
        let estimate: GasPriceEstimate

        var body: some View {
            CardView(title: "Priority Fee Ranges") {
                VStack(spacing: 12) {
                    DataRowView(
                        title: "Recent",
                        value: estimate.latestPriorityFeeDisplay,
                        trend: estimate.priorityFeeTrendDirection
                    )

                    DataRowView(
                        title: "Historical",
                        value: estimate.historicalPriorityFeeDisplay,
                        trend: nil
                    )
                }
            }
        }
    }

    // MARK: - Network Congestion View
    struct NetworkCongestionView: View {
        let estimate: GasPriceEstimate

        var body: some View {
            CardView(title: "Network Status") {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            PrimaryText(estimate.congestionLevel.displayName)
                                .fontWeight(.semibold)
                            SecondaryText("Congestion")
                        }

                        Spacer()

                        CongestionIndicator(level: estimate.congestionLevel)
                    }

                    HStack {
                        SecondaryText("Activity: \(estimate.networkCongestionDisplay)")
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Congestion Indicator
    struct CongestionIndicator: View {
        let level: CongestionLevel

        var body: some View {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(getColor(for: index))
                        .frame(width: 8, height: CGFloat(8 + index * 4))
                }
            }
        }

        private func getColor(for index: Int) -> Color {
            let isActive = index < activeBars
            return isActive ? level.color : Color.textSecondary.opacity(0.3)
        }

        private var activeBars: Int {
            switch level {
            case .low: return 1
            case .medium: return 2
            case .high: return 3
            }
        }
    }

    // MARK: - Fee Estimate Row
    struct GasFeeEstimateRow: View {
        let urgency: UrgencyLevel
        let feeDetails: GasPriceEstimate.FeeDetails

        var body: some View {
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        PrimaryText(urgency.displayName)
                            .fontWeight(.semibold)
                        SecondaryText(urgency.description)
                            .font(.caption)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        PrimaryText(feeDetails.maxFeeDisplay)
                            .fontWeight(.medium)
                        SecondaryText(feeDetails.waitTimeDisplay)
                            .font(.caption)
                    }
                }

                if urgency != .high {
                    Divider()
                        .background(Color.textSecondary.opacity(0.2))
                }
            }
        }
    }

    // MARK: - Data Row View
    struct DataRowView: View {
        let title: String
        let value: String
        let trend: TrendDirection?

        var body: some View {
            HStack {
                PrimaryText(title)
                    .fontWeight(.medium)

                Spacer()

                HStack(spacing: 4) {
                    PrimaryText(value)

                    if let trend = trend, trend != .stable {
                        SystemImage(trend.icon)
                            .foregroundStyle(trend.color)
                            .font(.caption)
                    }
                }
            }
        }
    }
}
