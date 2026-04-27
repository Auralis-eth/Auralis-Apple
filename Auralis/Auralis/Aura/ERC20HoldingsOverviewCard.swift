import SwiftUI

struct ERC20HoldingsOverviewCard: View {
    let walletAddress: String
    let chainTitle: String
    let holdingsSubtitle: String
    let freshnessTitle: String
    let nativeHoldingCount: Int
    let tokenHoldingCount: Int
    let isSyncing: Bool

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 30, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                AuraTrustLabel(kind: .provider)

                AuraSectionHeader(
                    title: "Token Scope",
                    subtitle: holdingsSubtitle
                ) {
                    AuraPill(
                        isSyncing ? "Syncing" : freshnessTitle,
                        systemImage: isSyncing ? "arrow.triangle.2.circlepath.circle.fill" : "clock.arrow.circlepath",
                        emphasis: isSyncing ? .accent : .neutral
                    )
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(walletAddress.displayAddress)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.textPrimary)

                        Text("\(chainTitle) wallet scope")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer(minLength: 12)
                }

                HStack(spacing: 10) {
                    metricCard(
                        title: "Native",
                        value: "\(nativeHoldingCount)",
                        systemImage: "bolt.fill"
                    )
                    metricCard(
                        title: "ERC-20",
                        value: "\(tokenHoldingCount)",
                        systemImage: "bitcoinsign.circle"
                    )
                }
            }
        }
    }

    private func metricCard(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)

            Text(value)
                .font(.title3.weight(.black))
                .foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}
