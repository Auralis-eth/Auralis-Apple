import SwiftData
import SwiftUI

private struct ObserveModePolicyView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var denialMessage: String?

    let modeState: ModeState
    let services: ShellServiceHub

    private let blockedActions: [PolicyControlledAction] = [
        .signMessage,
        .approveSpending,
        .draftTransaction
    ]

    var body: some View {
        AuraScenicScreen(contentAlignment: .top) {
            VStack(alignment: .leading, spacing: 16) {
                ShellStatusCard(
                    eyebrow: "Observe Mode",
                    title: "Execution Is Locked",
                    message: "Auralis is currently read-only. Signing, approvals, and transaction drafting stay blocked until a later phase unlocks them intentionally.",
                    systemImage: "eye.slash",
                    tone: .warning
                )

                ForEach(blockedActions, id: \.rawValue) { action in
                    AuraSurfaceCard(style: .soft, cornerRadius: 24, padding: 16) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(action.title)
                                    .font(.headline)
                                    .foregroundStyle(Color.textPrimary)

                                Text(action.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                            }

                            Spacer(minLength: 8)

                            AuraActionButton("Try", style: .surface) {
                                attempt(action)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .alert("Not available in Observe mode", isPresented: denialAlertBinding) {
            Button("OK", role: .cancel) {
                denialMessage = nil
            }
        } message: {
            Text(denialMessage ?? "This action is not available right now.")
        }
    }

    private var denialAlertBinding: Binding<Bool> {
        Binding(
            get: { denialMessage != nil },
            set: { isPresented in
                if !isPresented {
                    denialMessage = nil
                }
            }
        )
    }

    private func attempt(_ action: PolicyControlledAction) {
        let result = services.policyActionHandlerFactory(modelContext, modeState).attempt(action)

        if !result.isAllowed {
            denialMessage = result.userMessage
        }
    }
}

struct BadgeLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.deepBlue.opacity(0.18))
            )
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
    }
}
