import SwiftUI

private struct AuraComponentPreviewMatrix: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AuraSectionHeader(
                    title: "Section Header",
                    subtitle: "Previewed at accessibility text sizes so wrapping and heading semantics stay visible."
                )

                AuraActionButton("Primary Action", systemImage: "sparkles", style: .hero) {}

                AuraSurfaceCard(style: .regular, cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Surface Card")
                            .font(.headline)
                        Text("Cards should keep readable spacing and opaque contrast fallbacks when accessibility display settings are enabled.")
                            .font(.body)
                    }
                }

                AuraEmptyState(
                    eyebrow: "Preview",
                    title: "Empty State",
                    message: "Actions remain separate controls and the message wraps cleanly at the largest accessibility text size.",
                    systemImage: "tray",
                    primaryAction: AuraFeedbackAction(title: "Retry", systemImage: "arrow.clockwise") {},
                    secondaryAction: AuraFeedbackAction(title: "Dismiss", systemImage: "xmark") {}
                )
            }
            .padding()
        }
        .background(Color.background)
    }
}

#Preview("Aura Components Accessibility5") {
    AuraComponentPreviewMatrix()
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Aura Components Dark Mode") {
    AuraComponentPreviewMatrix()
        .preferredColorScheme(.dark)
}

#Preview("Aura Components Large Text (Canvas Increase Contrast)") {
    AuraComponentPreviewMatrix()
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Aura Components (Canvas Reduce Transparency)") {
    AuraComponentPreviewMatrix()
}

#Preview("Aura Components (Canvas Reduce Motion + Transparency)") {
    AuraComponentPreviewMatrix()
}

#Preview("Aura Components Light (Canvas Increase Contrast)") {
    AuraComponentPreviewMatrix()
        .preferredColorScheme(.light)
}
