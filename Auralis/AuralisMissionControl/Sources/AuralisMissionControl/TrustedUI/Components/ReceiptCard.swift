import SwiftUI

/// A trusted component that renders a resolved, sanitized ``TrustedUIReceiptSummary``. The registry
/// resolves the `receiptID` into this value, so this view never touches the receipt/storage packages.
public struct ReceiptCard: View {
    private let summary: TrustedUIReceiptSummary

    public init(summary: TrustedUIReceiptSummary) {
        self.summary = summary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .font(.headline)
                    Text(summary.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if !summary.fields.isEmpty {
                Divider()
                // Positional identity, not `Field.id`. `Field.id` is its `key`, and nothing stops a
                // summary carrying the same key twice — a resolver flattening a receipt with two
                // `amount` entries is the obvious case. `ForEach` over colliding ids draws one row
                // for the pair, so a receipt would under-report what it recorded.
                ForEach(Array(summary.fields.enumerated()), id: \.offset) { _, field in
                    HStack(alignment: .firstTextBaseline) {
                        Text(field.key)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(field.value)
                            .font(.caption.monospaced())
                            .multilineTextAlignment(.trailing)
                    }
                    // Keeps the value attached to the key that says what it is, as in `ApprovalSheet`.
                    .accessibilityElement(children: .combine)
                }
            }

            HStack {
                Text(summary.actorLabel)
                Spacer(minLength: 0)
                // Date *and* time: a receipt is the audit record of a specific act, and several
                // receipts for the same capability on one day are routine. Rendered as `.date`
                // alone they were indistinguishable, and the ordering a person reads off the list
                // could not be checked against the card.
                Text(summary.timestamp, format: .dateTime.year().month().day().hour().minute())
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(TrustedUIA11yID.receiptCard)
    }
}
