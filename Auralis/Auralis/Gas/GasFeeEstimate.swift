//
//  GasFeeEstimate.swift
//  KickingHorse
//
//  Created by Daniel Bell on 10/1/24.
//

import AuralisPrimaryModels
import Observation
import ProviderKit
import SwiftUI
import AuraUI
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

    var symbolName: String {
        switch self {
        case .low: return "1.circle.fill"
        case .medium: return "2.circle.fill"
        case .high: return "3.circle.fill"
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
    private(set) var lastCompletedPhase: Phase?

    private let provider: any GasPricingProviding
    private var currentTask: Task<Void, Never>?
    private var refreshTimer: Timer?

    init(provider: any GasPricingProviding) {
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
        lastCompletedPhase = nil

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
                self.lastCompletedPhase = .loaded
            }
        } catch {
            if !Task.isCancelled && currentChain?.chainId == chain.chainId {
                self.estimate = nil
                self.error = error
                self.lastUpdated = nil
                self.isShowingCachedEstimate = false
                self.phase = .failed
                self.lastCompletedPhase = .failed
            }
        }
    }
}

// MARK: - Main View
struct GasPriceEstimateView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var chain: Chain
    @State private var viewModel: GasPriceEstimateViewModel

    private var haptics: AuraHaptics {
        AuraHaptics(accessibilityReduceMotion: accessibilityReduceMotion)
    }

    init(
        chain: Binding<Chain>,
        provider: any GasPricingProviding
    ) {
        self.init(
            chain: chain,
            viewModel: GasPriceEstimateViewModel(provider: provider)
        )
    }

    init(
        chain: Binding<Chain>,
        viewModel: GasPriceEstimateViewModel
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
        .onChange(of: viewModel.phase) { _, phase in
            if phase == .loading {
                AuraAccessibilityAnnouncer.announce(String(localized: "Fetching gas prices"))
            }
        }
        .onChange(of: viewModel.lastCompletedPhase) { _, phase in
            switch phase {
            case .loaded:
                AuraAccessibilityAnnouncer.announce(String(localized: "Gas prices updated"))
            case .failed:
                AuraAccessibilityAnnouncer.announce(String(localized: "Gas prices unavailable"))
            case .initial, .loading, .none:
                break
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let estimate = viewModel.estimate {
            ScrollView {
                LazyVStack(spacing: 16) {
                    FeeEstimateCardView(estimate: estimate)

                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 12) {
                            BaseFeeCardView(estimate: estimate)
                            NetworkCongestionView(estimate: estimate)
                        }
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                BaseFeeCardView(estimate: estimate)
                                NetworkCongestionView(estimate: estimate)
                            }

                            VStack(spacing: 12) {
                                BaseFeeCardView(estimate: estimate)
                                NetworkCongestionView(estimate: estimate)
                            }
                        }
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
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(chainName) Gas Tracker")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let lastUpdatedText {
                        Text(lastUpdatedText)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                AuraPill(
                    statusTitle,
                    systemImage: statusSystemImage,
                    emphasis: statusEmphasis
                )
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "\(chainName) gas tracker"))
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
                .accessibilityLabel(String(localized: "Fetching gas prices"))
                .accessibilityAddTraits(.updatesFrequently)
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
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

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
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            CardView(title: "Network Status") {
                VStack(spacing: 12) {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            congestionSummary
                            activitySummary
                        }
                    } else {
                        HStack {
                            congestionSummary
                            Spacer()
                            CongestionIndicator(level: estimate.congestionLevel)
                        }

                        HStack {
                            activitySummary
                            Spacer()
                        }
                    }
                }
            }
        }

        private var congestionSummary: some View {
            VStack(alignment: .leading, spacing: 4) {
                PrimaryText(estimate.congestionLevel.displayName)
                    .fontWeight(.semibold)
                SecondaryText("Congestion")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Congestion"))
            .accessibilityValue(String(localized: "\(estimate.congestionLevel.displayName)"))
        }

        private var activitySummary: some View {
            SecondaryText("Activity: \(estimate.networkCongestionDisplay)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Activity"))
                .accessibilityValue(String(localized: "\(estimate.networkCongestionDisplay)"))
        }
    }

    // MARK: - Congestion Indicator
    struct CongestionIndicator: View {
        let level: CongestionLevel
        @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

        var body: some View {
            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(getColor(for: index))
                            .frame(width: 8, height: CGFloat(8 + index * 4))
                    }
                }

                if differentiateWithoutColor {
                    Label(level.displayName, systemImage: level.symbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(level.color)
                }
            }
            .accessibilityHidden(true)
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
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(spacing: 8) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        labelContent
                        valueContent
                    }
                } else {
                    HStack {
                        labelContent
                        Spacer()
                        valueContent
                    }
                }

                if urgency != .high {
                    Divider()
                        .background(Color.textSecondary.opacity(0.2))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "\(urgency.displayName)"))
            .accessibilityValue(String(localized: "\(urgency.description). Maximum fee \(feeDetails.maxFeeDisplay). Wait time \(feeDetails.waitTimeDisplay)"))
        }

        private var labelContent: some View {
            VStack(alignment: .leading, spacing: 2) {
                PrimaryText(urgency.displayName)
                    .fontWeight(.semibold)
                SecondaryText(urgency.description)
                    .font(.caption)
            }
        }

        private var valueContent: some View {
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                PrimaryText(feeDetails.maxFeeDisplay)
                    .fontWeight(.medium)
                SecondaryText(feeDetails.waitTimeDisplay)
                    .font(.caption)
            }
        }
    }

    // MARK: - Data Row View
    struct DataRowView: View {
        let title: String
        let value: String
        let trend: TrendDirection?
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

        var body: some View {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        titleText
                        valueContent
                    }
                } else {
                    HStack {
                        titleText
                        Spacer()
                        valueContent
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "\(title)"))
            .accessibilityValue(accessibilityValue)
        }

        private var titleText: some View {
            PrimaryText(title)
                .fontWeight(.medium)
        }

        private var valueContent: some View {
            HStack(spacing: 4) {
                PrimaryText(value)

                if let trend = trend, trend != .stable {
                    if differentiateWithoutColor {
                        Label(trendShortLabel(for: trend), systemImage: trend.icon)
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(trend.color)
                            .font(.caption)
                            .accessibilityLabel(String(localized: "\(trendAccessibilityLabel(for: trend))"))
                    } else {
                        Label(trendShortLabel(for: trend), systemImage: trend.icon)
                            .labelStyle(.iconOnly)
                            .foregroundStyle(trend.color)
                            .font(.caption)
                            .accessibilityLabel(String(localized: "\(trendAccessibilityLabel(for: trend))"))
                    }
                }
            }
        }

        private var accessibilityValue: String {
            guard let trend, trend != .stable else {
                return value
            }
            return "\(value). \(trendAccessibilityLabel(for: trend))"
        }

        private func trendAccessibilityLabel(for trend: TrendDirection) -> String {
            switch trend {
            case .up:
                return "Trending up"
            case .down:
                return "Trending down"
            case .stable:
                return "Stable"
            }
        }

        private func trendShortLabel(for trend: TrendDirection) -> String {
            switch trend {
            case .up:
                return String(localized: "Up")
            case .down:
                return String(localized: "Down")
            case .stable:
                return String(localized: "Stable")
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
                return "Auralis could not load gas prices because the provider returned HTTP \(statusCode)."
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
        case .rpcError:
            return "Auralis could not load gas prices because the provider reported an error."
        }
    }
}
