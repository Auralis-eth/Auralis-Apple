import SwiftData
import SwiftUI

struct GlobalChromeView: View {
    let snapshot: ContextSnapshot
    let onOpenAccountSwitcher: () -> Void
    let onOpenContextInspector: () -> Void
    let onOpenSearch: () -> Void

    var body: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 26, padding: 16) {
            HStack {
                accountButton

                Spacer(minLength: 8)

                AuraPill(
                    systemImage: "eye",
                    emphasis: .accent,
                    imageSize: .title3.weight(.semibold),
                    accessibilityLabel: snapshot.modeDisplay
                )
                .accessibilityHint("Mode is sourced from the shared shell context snapshot.")
                
                Button(action: onOpenContextInspector) {
                    AuraPill(
                        systemImage: "gyroscope",
                        emphasis: .accent,
                        imageSize: .title3.weight(.semibold),
                        accessibilityLabel: snapshot.freshnessLabel
                    )
                    .accessibilityHidden(true)
                }
                .accessibilityLabel("Context")
                .accessibilityValue(snapshot.freshnessLabel)
                .accessibilityHint("Shows scope and freshness details for \(snapshot.scopeSummary).")

                Button(action: onOpenSearch) {
                    AuraPill(
                        systemImage: "magnifyingglass",
                        emphasis: .accent,
                        imageSize: .title3.weight(.semibold),
                        accessibilityLabel: "Search"
                    )
                    .accessibilityHidden(true)
                }
                .accessibilityLabel("Search")
                .accessibilityHint("Opens global search.")
                
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var accountButton: some View {
        Button(action: onOpenAccountSwitcher) {
            HStack(alignment: .top, spacing: 10) {
                SystemImage("person.crop.circle")
                    .font(.title3)
                    .accessibilityHidden(true)

                Text(accountTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Current account")
        .accessibilityValue(accountTitle)
        .accessibilityHint("Opens the account switcher.")
    }

    private var accountTitle: String {
        snapshot.chromeAccountTitle
    }
}

struct ChromeContextInspectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(
        sort: [
            SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
            SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
        ]
    ) private var storedReceipts: [StoredReceipt]

    let contextService: ContextService
    let onRefreshContext: @MainActor () async -> Void
    let onOpenReceipt: (String) -> Void

    @State private var isRefreshingContext = false

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

    private var contextReceipts: [ReceiptTimelineRecord] {
        guard let receiptScope else {
            return []
        }

        return storedReceipts
            .map(ReceiptTimelineRecord.init)
            .filter {
                $0.trigger == "context.built" && $0.matches(receiptScope)
            }
    }

    private var latestContextReceipt: ReceiptTimelineRecord? {
        contextReceipts.first
    }

    private var relatedContextReceipts: [ReceiptTimelineRecord] {
        guard let correlationID = latestContextReceipt?.correlationID, !correlationID.isEmpty else {
            return []
        }

        return storedReceipts
            .map(ReceiptTimelineRecord.init)
            .filter {
                $0.correlationID == correlationID && $0.id != latestContextReceipt?.id
            }
    }

    private var shouldOfferRefresh: Bool {
        snapshot.freshness.refreshState == .unknown
            || snapshot.freshness.lastSuccessfulRefreshAt == nil
            || snapshot.freshness.isStale
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Schema") {
                    LabeledContent("Version", value: snapshot.version.rawValue)
                }

                Section("Mode") {
                    LabeledContent("Current Mode", value: snapshot.modeDisplay)
                    LabeledContent("Mode Provenance", value: snapshot.mode.provenance.displayLabel)
                }

                Section("Scope") {
                    LabeledContent("Account", value: snapshot.accountDisplay)
                    LabeledContent("Account Provenance", value: snapshot.scope.accountAddress.provenance.displayLabel)
                    LabeledContent("Chains", value: snapshot.selectedChainDisplayNames)
                    LabeledContent("Chain Provenance", value: snapshot.scope.selectedChains.provenance.displayLabel)
                    LabeledContent("Summary", value: snapshot.scopeSummary)
                }

                Section("Library Pointers") {
                    LabeledContent(
                        "Tracked NFTs",
                        value: snapshot.libraryPointers.trackedNFTCount.value.map(String.init) ?? "Not loaded yet"
                    )
                    LabeledContent(
                        "Playlists",
                        value: snapshot.libraryPointers.musicCollectionCount.value.map(String.init) ?? "Not loaded yet"
                    )
                    LabeledContent(
                        "Receipts",
                        value: snapshot.libraryPointers.receiptCount.value.map(String.init) ?? "Not loaded yet"
                    )
                    LabeledContent("Summary", value: snapshot.librarySummary)
                }

                Section("Preferences") {
                    LabeledContent(
                        "Demo Data",
                        value: booleanLabel(snapshot.localPreferences.prefersDemoData.value)
                    )
                    LabeledContent(
                        "Pinned Items",
                        value: snapshot.localPreferences.pinnedItemCount.value.map(String.init) ?? "Not configured"
                    )
                    LabeledContent("Summary", value: snapshot.preferencesSummary)
                }

                Section("Balances") {
                    LabeledContent(
                        "Native Balance",
                        value: snapshot.balances.nativeBalanceDisplay.value ?? "Deferred to provider-backed balance work"
                    )
                    LabeledContent(
                        "Balance Provenance",
                        value: snapshot.balances.nativeBalanceDisplay.provenance.displayLabel
                    )
                    LabeledContent(
                        "Balance Updated",
                        value: formattedTimestamp(snapshot.balances.nativeBalanceDisplay.updatedAt)
                    )
                }

                Section("Freshness") {
                    LabeledContent("Refresh State", value: snapshot.freshness.refreshState.displayLabel)
                    LabeledContent("Freshness Status", value: snapshot.freshnessLabel)
                    if snapshot.freshness.isStale {
                        Text("This context is older than the current freshness window for this scope.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    if let ttl = snapshot.freshness.ttl {
                        LabeledContent(
                            "TTL",
                            value: Duration.seconds(ttl).formatted(.units(allowed: [.minutes, .seconds]))
                        )
                    }
                    LabeledContent(
                        "Last Refresh Provenance",
                        value: snapshot.freshness.lastSuccessfulRefreshProvenance.displayLabel
                    )
                    LabeledContent(
                        "Last Successful Refresh",
                        value: formattedTimestamp(snapshot.freshness.lastSuccessfulRefreshAt)
                    )
                    if isRefreshingContext || snapshot.freshness.refreshState == .refreshing {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Refreshing active scope…")
                                .foregroundStyle(Color.textSecondary)
                        }
                    } else if shouldOfferRefresh {
                        Button {
                            refreshContext()
                        } label: {
                            Label("Refresh Active Scope", systemImage: "arrow.clockwise")
                        }
                    }
                }

                Section("Why Am I Seeing This?") {
                    Text("This inspector reflects the active shell scope, current mode, local context cache, and the most recent refresh state for \(snapshot.scopeSummary).")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }

                Section("Related Receipts") {
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
                                    Text("\(relatedContextReceipts.count) related receipt(s) share this correlation flow.")
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("contextInspector.receipt.latest")
                    } else {
                        Text("No related context receipt has been recorded for this scope yet.")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .navigationTitle("Context Inspector")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formattedTimestamp(_ date: Date?) -> String {
        guard let date else {
            return "Unknown"
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func booleanLabel(_ value: Bool?) -> String {
        switch value {
        case true:
            return "Enabled"
        case false:
            return "Disabled"
        case nil:
            return "Unknown"
        }
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

    private func receiptDetailSummary(for receipt: ReceiptTimelineRecord) -> String {
        let timestamp = receipt.createdAt.formatted(date: .abbreviated, time: .shortened)
        let correlation = receipt.correlationID.map { "Flow \($0.prefix(8))" } ?? "No correlation"
        return "\(timestamp) • \(correlation)"
    }
}

private extension ContextProvenance {
    var displayLabel: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private extension ContextRefreshState {
    var displayLabel: String {
        rawValue.capitalized
    }
}
