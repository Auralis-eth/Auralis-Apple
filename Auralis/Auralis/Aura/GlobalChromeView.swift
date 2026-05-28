import AuralisPrimaryModels
import SwiftData
import SwiftUI
import AuraUI

struct GlobalChromeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let snapshot: ContextSnapshot
    let onOpenAccountSwitcher: () -> Void
    let onOpenContextInspector: (() -> Void)?
    let onOpenSearch: () -> Void

    var body: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 26, padding: 16) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    accountButton

                    HStack(alignment: .top, spacing: 8) {
                        modePill
                        contextInspectorButton
                        searchButton
                        Spacer(minLength: 0)
                    }
                }
            } else {
                HStack {
                    accountButton

                    Spacer(minLength: 8)

                    modePill
                    contextInspectorButton
                    searchButton
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var modePill: some View {
        AuraPill(
            snapshot.modeDisplay,
            systemImage: "eye",
            emphasis: .accent,
            imageSize: .title3.weight(.semibold),
            accessibilityLabel: snapshot.modeDisplay
        )
        .accessibilityHint(
            String(
                localized: "Shows the current viewing mode for this wallet."
            )
        )
    }

    @ViewBuilder
    private var contextInspectorButton: some View {
        if let onOpenContextInspector {
            Button(action: onOpenContextInspector) {
                if dynamicTypeSize.isAccessibilitySize {
                    Label(snapshot.freshnessLabel, systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemBackground), in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                        }
                        .accessibilityHidden(true)
                } else {
                    AuraPill(
                        snapshot.freshnessLabel,
                        systemImage: "clock.arrow.circlepath",
                        emphasis: .accent,
                        imageSize: .title3.weight(.semibold),
                        accessibilityLabel: String(localized: "Wallet status")
                    )
                    .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(String(localized: "Wallet status"))
            .accessibilityValue(snapshot.freshnessLabel)
            .accessibilityHint(
                String(
                    localized: "Shows wallet details, sync status, and recent updates for \(snapshot.scopeSummary)."
                )
            )
        }
    }

    private var searchButton: some View {
        Button(action: onOpenSearch) {
            AuraPill(
                systemImage: "magnifyingglass",
                emphasis: .accent,
                imageSize: .title3.weight(.semibold),
                accessibilityLabel: String(localized: "Search")
            )
            .accessibilityHidden(true)
        }
        .accessibilityLabel(String(localized: "Search"))
        .accessibilityHint(String(localized: "Opens global search."))
    }

    private var accountButton: some View {
        Button(action: onOpenAccountSwitcher) {
            HStack(alignment: .top, spacing: 10) {
                SystemImage("person.crop.circle")
                    .font(.title3)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(accountTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

                    Text(snapshot.selectedChainDisplayNames)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Current account"))
        .accessibilityValue(String(localized: "\(accountTitle), \(snapshot.selectedChainDisplayNames)"))
        .accessibilityHint(String(localized: "Opens the account switcher."))
    }

    private var accountTitle: String {
        snapshot.chromeAccountTitle
    }
}

struct ChromeContextInspectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let contextService: ContextService
    let onRefreshContext: @MainActor () async -> Void
    let onOpenReceipt: (String) -> Void

    @State private var isRefreshingContext = false
    @State private var latestContextReceipt: ReceiptTimelineRecord?
    @State private var relatedContextReceipts: [ReceiptTimelineRecord] = []

    private var snapshot: ContextSnapshot {
        contextService.snapshot
    }

    private var receiptScope: ReceiptTimelineScope? {
        guard let chain = snapshot.scope.selectedChains.value?.first else {
            return nil
        }

        return ReceiptTimelineScope(
            accountAddress: snapshot.scope.accountAddress.value ?? "",
            chain: chain
        )
    }

    private var shouldOfferRefresh: Bool {
        snapshot.freshness.refreshState == .unknown
            || snapshot.freshness.lastSuccessfulRefreshAt == nil
            || snapshot.freshness.isStale
    }

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "Wallet")) {
                    LabeledContent(String(localized: "Account"), value: snapshot.accountDisplay)
                    LabeledContent(String(localized: "Networks"), value: snapshot.selectedChainDisplayNames)
                    LabeledContent(String(localized: "Viewing Mode"), value: snapshot.modeDisplay)
                    LabeledContent(String(localized: "Summary"), value: snapshot.scopeSummary)
                }

                Section(String(localized: "Library")) {
                    LabeledContent(
                        String(localized: "Tracked NFTs"),
                        value: snapshot.libraryPointers.trackedNFTCount.value.map(String.init)
                            ?? String(localized: "Not loaded yet")
                    )
                    LabeledContent(
                        String(localized: "Playlists"),
                        value: snapshot.libraryPointers.musicCollectionCount.value.map(String.init)
                            ?? String(localized: "Not loaded yet")
                    )
                    LabeledContent(
                        String(localized: "Receipts"),
                        value: snapshot.libraryPointers.receiptCount.value.map(String.init)
                            ?? String(localized: "Not loaded yet")
                    )
                    LabeledContent(String(localized: "Summary"), value: snapshot.librarySummary)
                }

                Section(String(localized: "Shortcuts")) {
                    ForEach(snapshot.modulePointers.items, id: \.routeID) { item in
                        LabeledContent(item.title) {
                            Text(modulePointerValue(item))
                        }
                    }
                    LabeledContent(String(localized: "Main"), value: snapshot.primaryModuleSummary)
                    LabeledContent(String(localized: "More"), value: snapshot.shortcutModuleSummary)
                    LabeledContent(String(localized: "Pinned"), value: snapshot.pinnedModuleSummary)
                }

                Section(String(localized: "Preferences")) {
                    LabeledContent(
                        String(localized: "Demo Data"),
                        value: booleanLabel(snapshot.localPreferences.prefersDemoData.value)
                    )
                    LabeledContent(
                        String(localized: "Pinned Items"),
                        value: snapshot.localPreferences.pinnedItemCount.value.map(String.init)
                            ?? String(localized: "None pinned")
                    )
                    LabeledContent(String(localized: "Summary"), value: snapshot.preferencesSummary)
                }

                Section(String(localized: "Balance")) {
                    LabeledContent(
                        String(localized: "Native Balance"),
                        value: snapshot.balances.nativeBalanceDisplay.value
                            ?? String(localized: "Unavailable")
                    )
                    LabeledContent(
                        String(localized: "Balance Source"),
                        value: snapshot.balances.nativeBalanceDisplay.provenance.userFacingLabel
                    )
                    LabeledContent(
                        String(localized: "Last Balance Update"),
                        value: formattedTimestamp(snapshot.balances.nativeBalanceDisplay.updatedAt)
                    )
                    if let statusMessage = snapshot.balances.nativeBalanceStatusMessage.value {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Section(String(localized: "Sync Status")) {
                    LabeledContent(
                        String(localized: "Status"),
                        value: snapshot.freshness.refreshState.displayLabel
                    )
                    LabeledContent(
                        String(localized: "Wallet Freshness"),
                        value: snapshot.freshnessLabel
                    )
                    if snapshot.freshness.isStale {
                        Text(
                            String(
                                localized: "This wallet view is older than the current freshness window for this account and network."
                            )
                        )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    if let ttl = snapshot.freshness.ttl {
                        LabeledContent(
                            String(localized: "Refresh Window"),
                            value: Duration.seconds(ttl).formatted(.units(allowed: [.minutes, .seconds]))
                        )
                    }
                    LabeledContent(
                        String(localized: "Last Successful Update"),
                        value: formattedTimestamp(snapshot.freshness.lastSuccessfulRefreshAt)
                    )
                    if isRefreshingContext || snapshot.freshness.refreshState == .refreshing {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(String(localized: "Refreshing wallet details…"))
                                .foregroundStyle(Color.textSecondary)
                        }
                    } else if shouldOfferRefresh {
                        Button {
                            refreshContext()
                        } label: {
                            Label(
                                String(localized: "Refresh Wallet Data"),
                                systemImage: "arrow.clockwise"
                            )
                        }
                        Text(
                            String(
                                localized: "Checks the latest wallet data for the current account and network."
                            )
                        )
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Section(String(localized: "About Wallet Status")) {
                    Text(
                        String(
                            localized: "Wallet Status shows the active account, selected network, saved library details, and the most recent sync state for \(snapshot.scopeSummary)."
                        )
                    )
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }

                Section(String(localized: "Recent Updates")) {
                    if let latestContextReceipt {
                        Button {
                            openReceipt(latestContextReceipt)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(latestContextReceipt.summary)
                                    .foregroundStyle(Color.textPrimary)
                                Text(receiptDetailSummary(for: latestContextReceipt))
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                                if !relatedContextReceipts.isEmpty {
                                    Text(
                                        String(
                                            localized: "\(relatedContextReceipts.count) related update(s) are connected to this refresh."
                                        )
                                    )
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(latestContextReceipt.summary)
                        .accessibilityValue(receiptDetailSummary(for: latestContextReceipt))
                        .accessibilityHint(String(localized: "Shows receipt details"))
                        .accessibilityIdentifier("contextInspector.receipt.latest")
                    } else {
                        Text(
                            String(
                                localized: "No recent wallet update has been recorded for this account and network yet."
                            )
                        )
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .navigationTitle(String(localized: "Wallet Status"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                }
            }
        }
        .task(id: receiptScope) {
            reloadContextReceipts()
        }
    }

    private func formattedTimestamp(_ date: Date?) -> String {
        guard let date else {
            return String(localized: "Unknown")
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func booleanLabel(_ value: Bool?) -> String {
        switch value {
        case true:
            return String(localized: "Enabled")
        case false:
            return String(localized: "Disabled")
        case nil:
            return String(localized: "Unknown")
        }
    }

    private func modulePointerValue(_ item: ContextModulePointer) -> String {
        let priority = item.priority.rawValue.capitalized
        if item.isPinned {
            return String(localized: "\(priority) • Pinned")
        }

        return priority
    }

    private func refreshContext() {
        guard !isRefreshingContext else {
            return
        }

        isRefreshingContext = true
        Task { @MainActor in
            await onRefreshContext()
            isRefreshingContext = false
        }
    }

    private func openReceipt(_ receipt: ReceiptTimelineRecord) {
        dismiss()
        onOpenReceipt(receipt.id.uuidString)
    }

    private func reloadContextReceipts() {
        do {
            let receipts = try ChromeContextRefreshService(modelContext: modelContext).contextReceipts(scope: receiptScope)
            latestContextReceipt = receipts.latest
            relatedContextReceipts = receipts.related
        } catch {
            latestContextReceipt = nil
            relatedContextReceipts = []
        }
    }

    private func receiptDetailSummary(for receipt: ReceiptTimelineRecord) -> String {
        let timestamp = receipt.createdAt.formatted(date: .abbreviated, time: .shortened)
        guard let correlationID = receipt.correlationID else {
            return timestamp
        }

        guard !correlationID.isEmpty else {
            return timestamp
        }

        return String(localized: "\(timestamp) • Activity reference available")
    }
}

private extension ContextProvenance {
    var userFacingLabel: String {
        switch self {
        case .userProvided:
            return "Set by you"
        case .onChain:
            return "Freshly fetched"
        case .localCache:
            return "Loaded from cache"
        }
    }
}

private extension ContextRefreshState {
    var displayLabel: String {
        switch self {
        case .idle:
            return String(localized: "Up to date")
        case .refreshing:
            return String(localized: "Refreshing now")
        case .unknown:
            return String(localized: "Not yet loaded")
        }
    }
}
