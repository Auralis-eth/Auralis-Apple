import AuralisPrimaryModels
import AuraUI
import AuralisReceipts
import SwiftData
import SwiftUI

struct ReceiptDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let route: ReceiptRoute
    let scope: ReceiptTimelineScope

    @State private var receipt: ReceiptTimelineRecord?
    @State private var relatedReceipts: [ReceiptTimelineRecord] = []

    private var detailTaskID: ReceiptDetailTaskID {
        ReceiptDetailTaskID(routeID: route.id, scope: scope)
    }

    var body: some View {
        Group {
            if let receipt {
                let presentation = ReceiptPresentation(receipt: receipt)
                AuraScenicScreen(horizontalPadding: 12, verticalPadding: 12) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ReceiptDetailSummaryCard(receipt: receipt)

                            ReceiptPostflightCard(presentation: presentation)

                            ReceiptPresentationSectionsCard(presentation: presentation)

                            ReceiptWorkTimelineCard(
                                currentReceipt: receipt,
                                relatedReceipts: relatedReceipts
                            )

                            ReceiptArtifactLinksCard(presentation: presentation)

                            ReceiptPayloadCard(payload: receipt.details)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .accessibilityIdentifier(A11yID.Receipts.detail)
            } else {
                AuraScenicScreen(contentAlignment: .center) {
                    AuraEmptyState(
                        eyebrow: "Receipts",
                        title: "Receipt Unavailable",
                        message: "The requested receipt could not be found in local storage.",
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
                .accessibilityIdentifier(A11yID.Receipts.detailUnavailable)
            }
        }
        .navigationTitle("Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: detailTaskID) {
            reloadReceipts()
        }
    }

    private func reloadReceipts() {
        guard let receiptID = UUID(uuidString: route.id) else {
            receipt = nil
            relatedReceipts = []
            return
        }

        do {
            let storedReceipt = try modelContext.fetch(
                Self.makeReceiptDescriptor(receiptID: receiptID, scope: scope)
            ).first

            guard let storedReceipt else {
                receipt = nil
                relatedReceipts = []
                return
            }

            let timelineRecord = ReceiptTimelineRecord(storedReceipt: storedReceipt)
            // Account scope only. The chain filter is a *list* control: applying it here made a receipt
            // the user navigated or deep-linked straight to report itself as "could not be found in
            // local storage" whenever it was recorded on a chain other than the shell's current one.
            guard timelineRecord.matchesAccountScope(scope) else {
                receipt = nil
                relatedReceipts = []
                return
            }

            receipt = timelineRecord
            relatedReceipts = try loadRelatedReceipts(for: timelineRecord)
        } catch {
            receipt = nil
            relatedReceipts = []
        }
    }

    private func loadRelatedReceipts(for receipt: ReceiptTimelineRecord) throws -> [ReceiptTimelineRecord] {
        guard let correlationID = receipt.correlationID, !correlationID.isEmpty else {
            return []
        }

        return try modelContext.fetch(
            Self.makeRelatedReceiptsDescriptor(
                correlationID: correlationID,
                excludingReceiptID: receipt.id,
                scope: scope
            )
        )
        .map(ReceiptTimelineRecord.init)
        // Account scope only, matching the detail receipt itself: a correlated receipt recorded on
        // another chain is still part of this receipt's story and hiding it breaks the audit trail.
        .filter { $0.matchesAccountScope(scope) }
    }

    private static func makeReceiptDescriptor(
        receiptID: UUID,
        scope: ReceiptTimelineScope
    ) -> FetchDescriptor<StoredReceipt> {
        // Shares `ReceiptTimelineRecord.accountKey` with `matches(_:)` so the predicate and the
        // in-memory comparison cannot diverge. What this actually changes is the **non-address**
        // case: `AuralisEthereumAddress.normalized` returns `nil` for anything that is not 40 hex
        // digits, which dropped the account narrowing entirely and fell back to a full fetch, while
        // `accountKey` falls through to `trimmed.lowercased()` — exactly what the write side stored —
        // so an ENS-style or otherwise non-address account key now narrows correctly.
        //
        // It does **not** fix the unprefixed-address hole, and must not be read as having done so:
        // `accountKey` tries `AuralisEthereumAddress.normalized` *first* and returns it on success, so
        // for any valid 40-hex address — prefixed, unprefixed, or checksummed — it yields the same
        // `0x…` string the old call did. The write side is the asymmetric half and still is:
        // `ReceiptAccountAddress.resolve` stores `trimmed.lowercased()` and deliberately adds no
        // prefix, and `ReceiptPayload.timelineAccountAddress` is free-form and normalized nowhere. A
        // row stored unprefixed therefore remains invisible to this predicate, permanently, and no
        // post-fetch filter can recover it — a filter can only narrow. Latent today because every
        // production writer supplies a `0x`-prefixed address; tracked as **F-100**. Closing it means
        // normalizing on the write path, which touches a hashed column.
        let normalizedAccountAddress = ReceiptTimelineRecord.accountKey(scope.accountAddress)

        if let normalizedAccountAddress, !normalizedAccountAddress.isEmpty {
            return FetchDescriptor(
                predicate: #Predicate<StoredReceipt> { storedReceipt in
                    storedReceipt.id == receiptID
                        && storedReceipt.accountAddress == normalizedAccountAddress
                }
            )
        }

        return FetchDescriptor(
            predicate: #Predicate<StoredReceipt> { storedReceipt in
                storedReceipt.id == receiptID
            }
        )
    }

    private static func makeRelatedReceiptsDescriptor(
        correlationID: String,
        excludingReceiptID: UUID,
        scope: ReceiptTimelineScope
    ) -> FetchDescriptor<StoredReceipt> {
        // Shares `ReceiptTimelineRecord.accountKey` with `matches(_:)` so the predicate and the
        // in-memory comparison cannot diverge. What this actually changes is the **non-address**
        // case: `AuralisEthereumAddress.normalized` returns `nil` for anything that is not 40 hex
        // digits, which dropped the account narrowing entirely and fell back to a full fetch, while
        // `accountKey` falls through to `trimmed.lowercased()` — exactly what the write side stored —
        // so an ENS-style or otherwise non-address account key now narrows correctly.
        //
        // It does **not** fix the unprefixed-address hole, and must not be read as having done so:
        // `accountKey` tries `AuralisEthereumAddress.normalized` *first* and returns it on success, so
        // for any valid 40-hex address — prefixed, unprefixed, or checksummed — it yields the same
        // `0x…` string the old call did. The write side is the asymmetric half and still is:
        // `ReceiptAccountAddress.resolve` stores `trimmed.lowercased()` and deliberately adds no
        // prefix, and `ReceiptPayload.timelineAccountAddress` is free-form and normalized nowhere. A
        // row stored unprefixed therefore remains invisible to this predicate, permanently, and no
        // post-fetch filter can recover it — a filter can only narrow. Latent today because every
        // production writer supplies a `0x`-prefixed address; tracked as **F-100**. Closing it means
        // normalizing on the write path, which touches a hashed column.
        let normalizedAccountAddress = ReceiptTimelineRecord.accountKey(scope.accountAddress)

        if let normalizedAccountAddress, !normalizedAccountAddress.isEmpty {
            return FetchDescriptor(
                predicate: #Predicate<StoredReceipt> { storedReceipt in
                    storedReceipt.correlationID == correlationID
                        && storedReceipt.id != excludingReceiptID
                        && storedReceipt.accountAddress == normalizedAccountAddress
                },
                sortBy: [
                    SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                    SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
                ]
            )
        }

        return FetchDescriptor(
            predicate: #Predicate<StoredReceipt> { storedReceipt in
                storedReceipt.correlationID == correlationID
                    && storedReceipt.id != excludingReceiptID
            },
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )
    }
}

private struct ReceiptDetailTaskID: Equatable {
    let routeID: String
    let scope: ReceiptTimelineScope
}

extension ReceiptPresentation {
    /// Builds the canonical receipt view-model from a timeline record. The presentation logic
    /// (sections, ordering, outcome, change rows, searchable text) lives once in `AuralisReceipts`
    /// so this tab and the Mission Control console can never drift.
    init(receipt: ReceiptTimelineRecord) {
        self.init(
            summary: receipt.summary,
            trigger: receipt.trigger,
            scope: receipt.scope,
            actor: receipt.actor.rawValue,
            mode: receipt.mode.rawValue,
            provenance: receipt.provenance,
            correlationID: receipt.correlationID,
            isSuccess: receipt.isSuccess,
            details: receipt.details.values
        )
    }
}

enum ReceiptPostflightOutcome: Equatable, Sendable {
    case noOp
    case draftOnly
    case artifactProducing
    case blocked

    init(_ kind: ReceiptOutcomeKind) {
        switch kind {
        case .noOp: self = .noOp
        case .draftOnly: self = .draftOnly
        case .artifactProducing: self = .artifactProducing
        case .blocked: self = .blocked
        }
    }

    var title: String {
        switch self {
        case .noOp:
            return "No Change"
        case .draftOnly:
            return "Draft Only"
        case .artifactProducing:
            return "Produced Artifact"
        case .blocked:
            return "Blocked"
        }
    }

    var detail: String {
        switch self {
        case .noOp:
            return "This completed without a persisted draft or artifact."
        case .draftOnly:
            return "This prepared work for review without committing an artifact."
        case .artifactProducing:
            return "This produced or updated at least one artifact."
        case .blocked:
            return "This stopped before applying the requested work."
        }
    }

    var systemImage: String {
        switch self {
        case .noOp:
            return "minus.circle"
        case .draftOnly:
            return "doc.badge.clock"
        case .artifactProducing:
            return "archivebox.fill"
        case .blocked:
            return "exclamationmark.triangle.fill"
        }
    }

    var emphasis: AuraPill.Emphasis {
        switch self {
        case .noOp, .draftOnly:
            return .neutral
        case .artifactProducing:
            return .success
        case .blocked:
            return .accent
        }
    }
}

private struct ReceiptPostflightCard: View {
    let presentation: ReceiptPresentation

    var body: some View {
        let outcome = ReceiptPostflightOutcome(presentation.outcome)
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        postflightDescription(outcome)
                        Spacer(minLength: 12)
                        outcomePill(outcome)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        postflightDescription(outcome)
                        outcomePill(outcome)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(presentation.changeRows) { row in
                        ReceiptDetailFact(label: row.label, value: row.value)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.Receipts.detailPostflight)
    }

    private func postflightDescription(_ outcome: ReceiptPostflightOutcome) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Postflight")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            Text(outcome.detail)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func outcomePill(_ outcome: ReceiptPostflightOutcome) -> some View {
        AuraPill(
            outcome.title,
            systemImage: outcome.systemImage,
            emphasis: outcome.emphasis
        )
    }
}

private struct ReceiptPresentationSectionsCard: View {
    let presentation: ReceiptPresentation

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Readable Receipt")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                if presentation.sections.isEmpty {
                    Text("No categorized receipt fields were recorded. The raw payload remains available below.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    ForEach(presentation.sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(section.rows) { row in
                                ReceiptDetailFact(label: row.label, value: row.value)
                            }
                        }
                        .accessibilityElement(children: .contain)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.Receipts.detailReadable)
    }
}

private struct ReceiptWorkTimelineCard: View {
    let currentReceipt: ReceiptTimelineRecord
    let relatedReceipts: [ReceiptTimelineRecord]

    private var records: [ReceiptTimelineRecord] {
        ([currentReceipt] + relatedReceipts)
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.sequenceID < $1.sequenceID
                }

                return $0.createdAt < $1.createdAt
            }
    }

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Timeline")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                ForEach(records) { record in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: record.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(record.isSuccess ? Color.green : Color.orange)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.summary)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)

                            Text("\(record.triggerTitle) • \(record.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(record.summary)
                    .accessibilityValue("\(record.statusTitle). \(record.triggerTitle). \(record.createdAt.formatted(date: .abbreviated, time: .shortened))")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.Receipts.detailTimeline)
    }
}

private struct ReceiptArtifactLinksCard: View {
    let presentation: ReceiptPresentation

    var body: some View {
        if !presentation.artifactIDs.isEmpty {
            AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Related Artifacts")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)

                    ForEach(presentation.artifactIDs, id: \.self) { artifactID in
                        ReceiptDetailFact(label: "Artifact ID", value: artifactID.uuidString)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(A11yID.Receipts.detailArtifacts)
        }
    }
}
