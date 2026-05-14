import SwiftUI
import AuraUI

struct AuraPlayUnavailableView: View {
    let message: String?
    let showsReinstallGuidance: Bool
    let retryAction: @MainActor () async -> Void

    var body: some View {
        AuraScenicScreen(contentAlignment: .center) {
            AuraSurfaceCard(style: .regular, cornerRadius: 28, padding: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Music Unavailable", systemImage: "speaker.slash")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text(message ?? "AuraPlay could not start on this launch. The rest of the app remains available.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)

                    if showsReinstallGuidance {
                        Text("If this keeps failing, delete and reinstall the app to rebuild local AuraPlay storage.")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Text("Auralis does not expose a dedicated Music diagnostics or support screen yet.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)

                    Button {
                        Task {
                            await retryAction()
                        }
                    } label: {
                        Label("Retry Music Setup", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .accessibilityHint("Attempts to reopen AuraPlay storage and restart music services")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Music")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auraplay.unavailable")
    }
}
