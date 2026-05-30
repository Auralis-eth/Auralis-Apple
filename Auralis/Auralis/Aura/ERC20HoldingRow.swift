import SwiftUI
import AuraUI

struct ERC20HoldingRow: View {
    let row: TokenHoldingRowModel
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 26, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                AuraTrustLabel(kind: .provider)

                HStack(alignment: .top, spacing: 14) {
                    tokenMark

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(row.title)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(row.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 12)

                            VStack(alignment: .trailing, spacing: 6) {
                                Text(row.amountDisplay)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(Color.textPrimary)
                                    .multilineTextAlignment(.trailing)

                                if row.canOpenDetail {
                                    Label("Open detail", systemImage: "arrow.up.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accent.opacity(0.9))
                                }
                            }
                        }

                        ViewThatFits(in: .vertical) {
                            HStack(spacing: 8) {
                                primaryPills
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                primaryPills
                            }
                        }
                    }
                }

                HStack(alignment: .center, spacing: 10) {
                    Label(row.updatedLabel, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)

                    Spacer(minLength: 8)

                    if let symbol = row.symbol, !symbol.isEmpty {
                        Text(symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .auraAccessibleSummary(
            label: row.title,
            value: accessibilityValue,
            hint: row.canOpenDetail ? String(localized: "Shows token details") : nil,
            traits: row.canOpenDetail ? .isButton : []
        )
    }

    private var tokenMark: some View {
        ZStack {
            Circle()
                .fill(markGradient)
                .frame(width: 48, height: 48)

            Text(row.symbolGlyph)
                .font(.subheadline.weight(.black))
                .foregroundStyle(Color.white.opacity(0.96))
        }
        .overlay(alignment: .bottomTrailing) {
            if differentiateWithoutColor {
                Image(systemName: row.statusGlyph)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .padding(4)
                    .background(Color.surface, in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHidden(true)
    }

    private var accessibilityValue: String {
        var parts = [
            row.subtitle,
            row.amountDisplay,
            row.kindTitle,
            row.updatedLabel
        ]

        if row.isPlaceholder {
            parts.append(String(localized: "Metadata pending"))
        }

        if row.isAmountHidden {
            parts.append(String(localized: "Amount hidden"))
        }

        if row.isMetadataStale {
            parts.append(String(localized: "Metadata stale"))
        }

        return parts.joined(separator: ". ")
    }

    @ViewBuilder
    private var primaryPills: some View {
        AuraPill(
            row.kindTitle,
            systemImage: row.kind == .native ? "bolt.fill" : "bitcoinsign.circle",
            emphasis: row.kind == .native ? .accent : .neutral
        )

        if row.isPlaceholder {
            AuraPill("Metadata Pending", systemImage: "sparkles", emphasis: .neutral)
        }

        if row.isAmountHidden {
            AuraPill("Amount Hidden", systemImage: "eye.slash", emphasis: .neutral)
        }

        if row.isMetadataStale {
            AuraPill("Stale", systemImage: "clock.arrow.circlepath", emphasis: .neutral)
        }
    }

    private var markGradient: LinearGradient {
        let colors: [Color]
        switch row.kind {
        case .native:
            colors = [Color.accent.opacity(0.95), Color.deepBlue.opacity(0.9)]
        case .erc20:
            if row.isMetadataStale {
                colors = [Color.orange.opacity(0.9), Color.accent.opacity(0.75)]
            } else if row.isPlaceholder {
                colors = [Color.deepBlue.opacity(0.95), Color.secondary.opacity(0.8)]
            } else {
                colors = [Color.secondary.opacity(0.9), Color.accent.opacity(0.8)]
            }
        }

        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension TokenHoldingRowModel {
    var kindTitle: String {
        switch kind {
        case .native:
            return "Native"
        case .erc20:
            return "ERC-20"
        }
    }

    var symbolGlyph: String {
        let source = (symbol?.isEmpty == false ? symbol : title)
            .map { String($0.prefix(2)).uppercased() }
        return (source?.isEmpty == false ? source : nil) ?? "TK"
    }

    var updatedLabel: String {
        "Updated \(updatedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    var statusGlyph: String {
        if isMetadataStale {
            return "clock.arrow.circlepath"
        }
        if isPlaceholder {
            return "sparkles"
        }
        switch kind {
        case .native:
            return "bolt.fill"
        case .erc20:
            return "bitcoinsign.circle"
        }
    }
}
