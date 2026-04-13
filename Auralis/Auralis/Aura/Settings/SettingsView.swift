import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    let currentAccountAddress: String
    let currentChain: Chain
    let services: ShellServiceHub

    @State private var isShowingResetConfirmation = false
    @State private var isResettingPrivacyData = false
    @State private var resetErrorMessage: String?
    @State private var resetSuccessMessage: String?

    private var providerStatuses: [Secrets.ConfigurationStatus] {
        Secrets.configurationStatuses()
    }

    var body: some View {
        List {
            Section("Environment") {
                LabeledContent(
                    "Active Account",
                    value: currentAccountAddress.isEmpty ? "None selected" : currentAccountAddress.displayAddress
                )
                LabeledContent("Chain Scope", value: currentChain.routingDisplayName)
            }

            Section("Provider Configuration") {
                AuraTrustLabel(kind: .provider)

                Text("Auralis reads its provider key from Info.plist, which is intended to be populated by xcconfig at build time.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)

                ForEach(providerStatuses) { status in
                    LabeledContent(status.provider.rawValue) {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(status.isConfigured ? "Configured" : "Missing")
                                .foregroundStyle(status.isConfigured ? Color.textPrimary : Color.error)

                            Text(status.sourceDescription)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }

            Section("Privacy") {
                Text("Clear local privacy and derived support data without deleting saved accounts. This reset clears receipts, search history, ENS cache, gas cache, and persisted token holdings.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)

                Button(role: .destructive) {
                    isShowingResetConfirmation = true
                } label: {
                    if isResettingPrivacyData {
                        Label("Clearing Local Privacy Data…", systemImage: "hourglass")
                    } else {
                        Label("Clear Local Privacy Data", systemImage: "trash")
                    }
                }
                .disabled(isResettingPrivacyData)

                if let resetSuccessMessage {
                    Text(resetSuccessMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }

                if let resetErrorMessage {
                    Text(resetErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.error)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Clear local privacy data?", isPresented: $isShowingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                resetPrivacyData()
            }
        } message: {
            Text("This removes receipts, search history, ENS cache, gas cache, and persisted token holdings on this device.")
        }
    }

    private func resetPrivacyData() {
        isResettingPrivacyData = true
        resetErrorMessage = nil
        resetSuccessMessage = nil

        Task {
            do {
                try await services.privacyResetServiceFactory(modelContext).resetLocalPrivacyData()
                await MainActor.run {
                    isResettingPrivacyData = false
                    resetSuccessMessage = "Local privacy data was cleared for this device."
                }
            } catch {
                await MainActor.run {
                    isResettingPrivacyData = false
                    resetErrorMessage = error.localizedDescription
                }
            }
        }
    }
}
