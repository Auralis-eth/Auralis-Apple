import SwiftUI

struct GlobalChromeView: View {
    let snapshot: ContextSnapshot
    let onOpenAccountSwitcher: () -> Void
    let onOpenContextInspector: () -> Void
    let onOpenSearch: () -> Void
    @Environment(\.modeState) private var modeState

    var body: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 26, padding: 16) {
            HStack {
                accountButton

                Spacer(minLength: 8)

                AuraPill(
                    systemImage: "eye",
                    emphasis: .accent,
                    imageSize: .title3.weight(.semibold),
                    aceessibilityLabel: modeState.mode.rawValue
                )
                .accessibilityHint("Mode badge is provided by global mode state.")
                
                Button(action: onOpenContextInspector) {
                    AuraPill(
                        systemImage: "gyroscope",
                        emphasis: .accent,
                        imageSize: .title3.weight(.semibold),
                        aceessibilityLabel: modeState.mode.rawValue
                    )
                    .accessibilityHidden(true)
                }
                .accessibilityLabel("Context")

                Button(action: onOpenSearch) {
                    AuraPill(
                        systemImage: "magnifyingglass",
                        emphasis: .accent,
                        imageSize: .title3.weight(.semibold),
                        aceessibilityLabel: "Search"
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
