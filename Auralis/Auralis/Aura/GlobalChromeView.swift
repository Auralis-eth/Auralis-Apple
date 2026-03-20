import SwiftUI

struct GlobalChromeView: View {
    @Binding var currentAccount: EOAccount?
    @Binding var currentAddress: String
    let currentChain: Chain
    let nftService: NFTService
    let router: AppRouter
    let onOpenAccountSwitcher: () -> Void
    let onOpenContextInspector: () -> Void
    @Environment(\.modeState) private var modeState

    var body: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 26, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    accountButton

                    Spacer(minLength: 8)

                    AuraPill(modeState.mode.rawValue, systemImage: "eye", emphasis: .accent)
                        .accessibilityHint("Mode badge is provided by global mode state.")
                }

                HStack(spacing: 12) {
                    freshnessPill

                    Spacer(minLength: 8)

                    chromeButton(
                        title: "Search",
                        systemImage: "magnifyingglass",
                        action: { router.selectedTab = .search }
                    )

                    chromeButton(
                        title: "Context",
                        systemImage: "slider.horizontal.3",
                        action: onOpenContextInspector
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var accountButton: some View {
        Button(action: onOpenAccountSwitcher) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle")
                    .font(.title3)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(accountTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Text(accountSubtitle)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Current account")
        .accessibilityValue("\(accountTitle), \(accountSubtitle)")
        .accessibilityHint("Opens the account switcher.")
    }

    private var freshnessPill: some View {
        AuraPill(freshnessTitle, systemImage: freshnessSystemImage, emphasis: freshnessEmphasis)
            .accessibilityLabel("Freshness")
            .accessibilityValue(freshnessAccessibilityValue)
    }

    private var accountTitle: String {
        if let name = currentAccount?.name, !name.isEmpty {
            return name
        }

        if !currentAddress.isEmpty {
            return currentAddress.displayAddress
        }

        return "No Account"
    }

    private var accountSubtitle: String {
        if !currentAddress.isEmpty {
            return "\(currentAddress.displayAddress) • \(currentChain.routingDisplayName)"
        }

        return currentChain.routingDisplayName
    }

    private var freshnessTitle: String {
        if nftService.isLoading {
            return "Syncing"
        }

        if let lastSuccessfulRefreshAt {
            let minutes = Int(max(0, Date().timeIntervalSince(lastSuccessfulRefreshAt) / 60))
            if minutes < 1 {
                return "Fresh now"
            }
            if minutes < 60 {
                return "\(minutes)m ago"
            }
            return "Stale"
        }

        return "Unknown"
    }

    private var freshnessSystemImage: String {
        if nftService.isLoading {
            return "arrow.triangle.2.circlepath"
        }

        if let lastSuccessfulRefreshAt,
           Date().timeIntervalSince(lastSuccessfulRefreshAt) >= 3_600 {
            return "exclamationmark.triangle"
        }

        return "clock"
    }

    private var freshnessEmphasis: AuraPill.Emphasis {
        if nftService.isLoading {
            return .accent
        }

        if let lastSuccessfulRefreshAt,
           Date().timeIntervalSince(lastSuccessfulRefreshAt) < 3_600 {
            return .success
        }

        return .neutral
    }

    private var lastSuccessfulRefreshAt: Date? {
        nftService.lastSuccessfulRefreshAt
    }

    private var freshnessAccessibilityValue: String {
        if nftService.isLoading {
            return "Refreshing data now"
        }

        if let lastSuccessfulRefreshAt {
            return "Last refreshed \(lastSuccessfulRefreshAt.formatted(.relative(presentation: .named)))"
        }

        return "No completed refresh yet"
    }

    private func chromeButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)

                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.surface.opacity(0.45), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

extension Chain {
    var routingDisplayName: String {
        switch self {
        case .ethMainnet:
            return "Ethereum"
        case .polygonMainnet:
            return "Polygon"
        case .arbMainnet:
            return "Arbitrum"
        case .optMainnet:
            return "Optimism"
        case .baseMainnet:
            return "Base"
        default:
            return rawValue.capitalized
        }
    }
}

struct ChromeContextInspectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modeState) private var modeState

    let currentAccount: EOAccount?
    let currentAddress: String
    let currentChain: Chain
    let nftService: NFTService

    var body: some View {
        NavigationStack {
            List {
                Section("Mode") {
                    LabeledContent("Current Mode", value: modeState.mode.rawValue)
                }

                Section("Scope") {
                    LabeledContent("Account", value: currentAccount?.name ?? currentAddress.displayAddress)
                    LabeledContent("Chain", value: currentChain.routingDisplayName)
                }

                Section("Freshness") {
                    LabeledContent("Refresh State", value: freshnessValue)
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

    private var freshnessValue: String {
        if nftService.isLoading {
            return "Refreshing now"
        }

        if let refreshedAt = nftService.lastSuccessfulRefreshAt {
            return refreshedAt.formatted(.dateTime.hour().minute())
        }

        return "No completed refresh"
    }
}
