import SwiftUI

/// A trusted component for a proactive, non-blocking suggestion. The optional action is surfaced as a
/// button whose handler is supplied by the trusted presenting layer, not by the suggestion's author.
public struct SuggestionCard: View {
    private let model: SuggestionCardModel
    private let onAction: (() -> Void)?

    public init(model: SuggestionCardModel, onAction: (() -> Void)? = nil) {
        self.model = model
        self.onAction = onAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.tint)
                    Text(model.title)
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                Text(model.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // The prose reads as one element; the button below stays its own.
            .accessibilityElement(children: .combine)
            if let actionLabel = model.actionLabel, let onAction {
                Button(actionLabel, action: onAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(TrustedUIA11yID.suggestionAction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        // `.contain`, not `.combine`. This card can carry a button, and a combined root merges its
        // children into one element — the button stops being a separately focusable control with a
        // button trait, and its identifier is discarded, so the only interactive thing on the card
        // is unreachable to both Voice Control and a UI test.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(TrustedUIA11yID.suggestionCard)
    }
}
