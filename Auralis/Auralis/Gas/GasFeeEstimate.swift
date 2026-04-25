//
//  GasFeeEstimate.swift
//  KickingHorse
//
//  Created by Daniel Bell on 10/1/24.
//

import Observation
import SwiftUI
import UIKit

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
@Observable
final class GasPriceEstimateViewModel {
    enum Phase: Equatable {
        case initial
        case loading
        case loaded
        case failed
    }

    private(set) var estimate: GasPriceEstimate?
    private(set) var isLoading = false
    private(set) var error: Error?
    private(set) var currentChain: Chain?
    private(set) var lastUpdated: Date?
    private(set) var phase: Phase = .initial
    private(set) var isShowingCachedEstimate = false

    private let provider: any GasPricingProviding
    private var currentTask: Task<Void, Never>?
    private var refreshTimer: Timer?

    init(provider: any GasPricingProviding = AlchemyGasPricingProvider()) {
        self.provider = provider
    }

    isolated deinit {
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
            isShowingCachedEstimate = false
        }

        currentChain = chain
        phase = .loading

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
            Task { @MainActor [weak self] in
                self?.handleAutoRefreshTick()
            }
        }
    }

    private func handleAutoRefreshTick() {
        guard !isLoading, currentTask == nil else { return }

        currentTask = Task { @MainActor [weak self] in
            guard let self else { return }

            defer {
                currentTask = nil
            }

            await fetchGasPrice()
        }
    }

    private func performFetch(for chain: Chain) async {
        isLoading = true
        error = nil
        phase = .loading

        defer {
            isLoading = false
        }

        do {
            let result = try await provider.gasPriceEstimate(for: chain)

            // Only update if we're still on the same chain and not cancelled
            if !Task.isCancelled && currentChain?.chainId == chain.chainId {
                self.estimate = result.estimate
                self.error = nil
                self.lastUpdated = result.fetchedAt
                self.isShowingCachedEstimate = result.source != .live
                self.phase = .loaded
            }
        } catch {
            if !Task.isCancelled && currentChain?.chainId == chain.chainId {
                self.estimate = nil
                self.error = error
                self.lastUpdated = nil
                self.isShowingCachedEstimate = false
                self.phase = .failed
            }
        }
    }
}

// MARK: - Main View
struct GasPriceEstimateView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Binding var chain: Chain
    @State private var viewModel: GasPriceEstimateViewModel

    private var haptics: AuraHaptics {
        AuraHaptics(accessibilityReduceMotion: accessibilityReduceMotion)
    }

    init(
        chain: Binding<Chain>,
        viewModel: GasPriceEstimateViewModel = GasPriceEstimateViewModel()
    ) {
        _chain = chain
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 12) {
            HeaderView(
                chainName: chain.networkName,
                lastUpdated: viewModel.lastUpdated,
                isLoading: viewModel.phase == .loading,
                isShowingCachedEstimate: viewModel.isShowingCachedEstimate
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
                haptics.impact(.light)
                await viewModel.fetchGasPrice()
            }
        } else if viewModel.phase == .failed {
            ErrorView(
                error: viewModel.error,
                onRetry: {
                    await viewModel.fetchGasPrice()
                }
            )
        } else {
            LoadingView()
        }
    }
}

extension GasPriceEstimateView {
    // MARK: - Header View
    struct HeaderView: View {
        let chainName: String
        let lastUpdated: Date?
        let isLoading: Bool
        let isShowingCachedEstimate: Bool

        var body: some View {
            VStack(spacing: 8) {
                AuraSectionHeader(
                    title: "\(chainName) Gas Tracker",
                    subtitle: lastUpdatedText
                ) {
                    AuraPill(
                        statusTitle,
                        systemImage: statusSystemImage,
                        emphasis: statusEmphasis
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
            let prefix = isShowingCachedEstimate ? "Last live update" : "Last updated"
            return "\(prefix): \(lastUpdated.formatted(.dateTime.hour().minute()))"
        }

        private var accessibilityValue: String {
            if let lastUpdatedText {
                return "\(statusTitle). \(lastUpdatedText)"
            }

            return statusTitle
        }

        private var statusTitle: String {
            if isLoading {
                return "Updating"
            }

            return isShowingCachedEstimate ? "Cached" : "Live"
        }

        private var statusSystemImage: String {
            if isLoading {
                return "arrow.triangle.2.circlepath"
            }

            return isShowingCachedEstimate ? "clock.arrow.circlepath" : "fuelpump"
        }

        private var statusEmphasis: AuraPill.Emphasis {
            if isLoading {
                return .neutral
            }

            return isShowingCachedEstimate ? .neutral : .accent
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
            guard let error else {
                return "Failed to fetch gas price estimate. Please try again later."
            }

            if let gasError = error as? AlchemyGasPricingProvider.GasPricingError {
                return gasError.userFacingMessage
            }

            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    return "Auralis could not load gas prices because this device appears to be offline."
                case .timedOut, .cannotConnectToHost:
                    return "Auralis could not load gas prices because the provider is temporarily unavailable."
                default:
                    break
                }
            }

            return "Auralis could not load gas prices for the selected chain just now. Try again in a moment."
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

extension AlchemyGasPricingProvider.GasPricingError {
    var userFacingMessage: String {
        switch self {
        case .unsupportedChain:
            return "Auralis cannot refresh gas prices for this chain yet."
        case .invalidConfiguration:
            return "Auralis could not refresh gas prices because this build is missing provider configuration."
        case .networkFailure(let underlying):
            if let urlError = underlying as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    return "Auralis could not load gas prices because this device appears to be offline."
                case .timedOut, .cannotConnectToHost:
                    return "Auralis could not load gas prices because the provider is temporarily unavailable."
                default:
                    break
                }
            }
            return "Auralis could not load gas prices because the provider did not respond cleanly."
        case .badStatus(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Auralis could not load gas prices because the provider returned HTTP \(statusCode) (\(message))."
            }
            return "Auralis could not load gas prices because the provider returned HTTP \(statusCode)."
        case .invalidResponse:
            return "Auralis could not load gas prices because the provider returned data it could not read."
        case .backoffOverflow:
            return "Auralis could not load gas prices because retry scheduling failed."
        case .rateLimited:
            return "The gas pricing provider is rate-limiting requests right now. Try again in a moment."
        case .unauthorized:
            return "Auralis could not refresh gas prices because the provider rejected this build's credentials."
        case .unsupportedMethod:
            return "Auralis could not refresh gas prices because the provider does not support the required method."
        case .rpcError(_, let message):
            return "Auralis could not load gas prices because the provider reported an error: \(message)"
        }
    }
}
