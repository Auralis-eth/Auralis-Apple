import OperatorCore
import SwiftUI

struct ExternalLinkConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let destination: ExternalLinkConfirmationDestination
    let onConfirm: @MainActor () -> Void

    var body: some View {
        AuraScenicScreen(horizontalPadding: 12, verticalPadding: 12, contentAlignment: .top) {
            ScrollView {
                AuraSurfaceCard(style: .soft, cornerRadius: 28, padding: 20) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Open External Link?")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Color.textPrimary)

                            Text("You’re leaving Auralis and opening Safari. Review the destination before continuing.")
                                .font(.body)
                                .foregroundStyle(Color.textSecondary)
                        }

                        AuraTrustLabel(kind: .link)

                        destinationField(title: "Destination", value: destination.label, font: .headline)
                        destinationField(title: "Host", value: destination.hostDisplay, font: .title3.weight(.semibold))
                        destinationField(title: "Path", value: destination.pathDisplay, font: .body.monospaced())
                        destinationField(title: "Full URL", value: destination.fullURLDisplay, font: .footnote.monospaced())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("externalLink.confirmationSheet")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    AuraActionButton("Open in Safari", systemImage: "safari", style: .hero) {
                        onConfirm()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Opens this approved destination in Safari.")
                    .accessibilityIdentifier("externalLink.confirm")

                    AuraActionButton("Cancel", systemImage: "xmark", style: .surface) {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Stays in Auralis and closes this confirmation sheet.")
                    .accessibilityIdentifier("externalLink.cancel")
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }

    private func destinationField(title: String, value: String, font: Font) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)

            Text(value)
                .font(font)
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ExternalLinkConfirmationSheet(
        destination: ExternalLinkConfirmationDestination(
            label: "OpenSea",
            url: URL(string: "https://opensea.io/assets/base/0xabc/1")!,
            hostDisplay: "opensea.io",
            pathDisplay: "/assets/base/0xabc/1",
            fullURLDisplay: "https://opensea.io/assets/base/0xabc/1"
        ),
        onConfirm: { }
    )
}
