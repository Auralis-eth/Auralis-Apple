import AuraUI
import SwiftUI

public struct ProvenancePanelView: View {
    public let presentation: AuraPlayProvenancePresentation
    public let copyContract: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsCopyConfirmation = false

    #if canImport(UIKit)
    private var haptics: AuraHaptics {
        AuraHaptics(accessibilityReduceMotion: reduceMotion)
    }
    #endif

    public init(
        presentation: AuraPlayProvenancePresentation,
        copyContract: @escaping (String) -> Void
    ) {
        self.presentation = presentation
        self.copyContract = copyContract
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ProvenanceValueRow(title: "Chain", value: presentation.chainName)
                    ProvenanceValueRow(title: "Collection", value: presentation.collectionName ?? "Unknown Collection")
                    ProvenanceValueRow(title: "Token Standard", value: presentation.tokenType ?? "Unknown")
                    ProvenanceValueRow(title: "Token ID", value: presentation.tokenID ?? "Unavailable")
                } header: {
                    Text("NFT")
                }

                Section {
                    if let contractAddress = presentation.contractAddress {
                        VStack(alignment: .leading, spacing: 10) {
                            ProvenanceValueRow(title: "Contract", value: contractAddress)
                            Button("Copy Contract", systemImage: "doc.on.doc") {
                                copyContract(contractAddress)
                                presentCopyConfirmation()
                            }
                            .accessibilityIdentifier(A11yID.AuraPlay.provenanceCopyContract)
                        }
                    } else {
                        ProvenanceValueRow(title: "Contract", value: "Unavailable")
                    }

                    if let explorerURL = presentation.explorerURL {
                        Link(destination: explorerURL) {
                            Label("Open in Explorer", systemImage: "safari")
                        }
                        .accessibilityIdentifier(A11yID.AuraPlay.provenanceExplorerLink)
                    }
                } header: {
                    Text("On-chain link")
                } footer: {
                    Text("AuraPlay displays provenance for transparency. It does not show prices, listings, offers, or trading actions.")
                }
            }
            .navigationTitle(presentation.title)
            .auraPlayInlineNavigationTitle()
            .overlay(alignment: .bottom) {
                if showsCopyConfirmation {
                    Label("Contract address copied", systemImage: "doc.on.doc.fill")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.opacity)
                        .accessibilityIdentifier(A11yID.AuraPlay.playerCopyToast)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.provenancePanel)
    }

    private func presentCopyConfirmation() {
        #if canImport(UIKit)
        haptics.notification(.success)
        #endif
        AuraAccessibilityAnnouncer.announce(String(localized: "Contract address copied"))
        withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .easeInOut(duration: 0.2)) {
            showsCopyConfirmation = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeOut(duration: 0.2)) {
                showsCopyConfirmation = false
            }
        }
    }
}

private struct ProvenanceValueRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
