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
    let contextService: ContextService

    private var snapshot: ContextSnapshot {
        contextService.snapshot
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
