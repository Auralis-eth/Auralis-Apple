import RuntimeCore
import SwiftUI

/// A trusted component that makes a governed ``ContextBundle`` visible: each field with its value,
/// data class, source, and freshness. Sensitive fields are shown as redacted rather than raw.
public struct ContextBundleCard: View {
    private let bundle: ContextBundle
    /// When `nil` (the default, and what the live console passes) field ages render through SwiftUI's
    /// `.relative` style, which re-reads the wall clock on its own and keeps ticking however long the
    /// surface stays open. Assigning a date *pins* that clock instead, which is what snapshot tests
    /// and previews need: `.relative` measures against the real clock no matter what reference date
    /// the surrounding model was pinned to, so the rendered age drifted with calendar time and the
    /// `context-populated` baseline went stale roughly monthly.
    private let referenceDate: Date?

    public init(bundle: ContextBundle, referenceDate: Date? = nil) {
        self.bundle = bundle
        self.referenceDate = referenceDate
    }

    /// One rendered field. Identity is *positional*, not the field key.
    ///
    /// `ContextBundle` does not enforce unique keys — `init` stores the array verbatim,
    /// `sizeViolations()` never looks for duplicates, and `field(_:)` just returns the first match.
    /// Iterating with `id: \.key` therefore hands `ForEach` colliding identities whenever a bundle
    /// carries the same key twice, and SwiftUI draws one row for the pair. On the surface whose
    /// stated job is making governed context visible, a second `address` field would silently not
    /// be drawn, and the row that is drawn gives no hint another value for that key exists.
    /// `nonisolated` because it is pure value data, not view state. `ContextBundleCard` is a `View`
    /// and therefore `@MainActor`, and a nested type inherits that isolation — so handing one of
    /// these back to a non-isolated caller crosses an isolation boundary with a non-`Sendable`
    /// value, which traps at runtime rather than failing to compile.
    nonisolated struct Row: Identifiable, Equatable {
        /// Index in `bundle.fields`, so duplicate keys stay distinct rows.
        let id: Int
        let key: String
        let value: String
        let dataClass: String
        let source: String?
        let lastRefreshed: Date?
    }

    nonisolated static func rows(for bundle: ContextBundle) -> [Row] {
        bundle.fields.enumerated().map { index, field in
            Row(
                id: index,
                key: field.key,
                value: TrustedUIContextRedaction.displayValue(field),
                dataClass: field.dataClass.rawValue,
                source: field.source?.rawValue,
                lastRefreshed: field.lastRefreshed
            )
        }
    }

    public var body: some View {
        let rows = Self.rows(for: bundle)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.tint)
                Text("Context bundle")
                    .font(.headline)
                Spacer(minLength: 0)
            }

            if rows.isEmpty {
                Text("No context fields in scope.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(TrustedUIA11yID.contextBundleEmpty)
            } else {
                ForEach(rows) { row in
                    fieldRow(row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(TrustedUIA11yID.contextBundleCard)
    }

    private func fieldRow(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.key)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text(row.value)
                    .font(.caption.monospaced())
                    .multilineTextAlignment(.trailing)
            }
            HStack(spacing: 8) {
                Text(row.dataClass)
                if let source = row.source {
                    Text("· \(source)")
                }
                if let refreshed = row.lastRefreshed {
                    if let referenceDate {
                        Text("· \(Self.age(of: refreshed, relativeTo: referenceDate)) ago")
                    } else {
                        Text("· \(refreshed, style: .relative) ago")
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        // Combined for the same reason `ApprovalSheet` combines its detail rows: uncombined, the key
        // and the value it labels become separate VoiceOver stops, so a long monospaced value is
        // read out with no statement of which field it belongs to.
        .accessibilityElement(children: .combine)
    }

    /// The gap between `date` and `reference` as a bare duration ("2 yrs, 11 mths").
    ///
    /// Deliberately *not* a relative phrase: the caller appends " ago", so a `RelativeDateTimeFormatter`
    /// string would read "2 yrs ago ago". Two units matches the shape SwiftUI's `.relative` style
    /// produces, so the pinned and live paths render the same way.
    private static func age(of date: Date, relativeTo reference: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.year, .month, .day, .hour, .minute, .second]
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        // Ordered so a `lastRefreshed` stamped marginally ahead of the reference date — the console
        // reads sources and renders in the same run loop — does not format as a negative duration.
        return formatter.string(from: min(date, reference), to: max(date, reference)) ?? ""
    }
}
