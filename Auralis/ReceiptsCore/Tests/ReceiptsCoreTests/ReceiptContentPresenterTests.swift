import Foundation
import ReceiptsCore
import Testing

/// Locks the shared receipt-presentation logic that both the Receipts tab and Mission Control
/// delegate to, so the two surfaces can never drift apart again.
struct ReceiptContentPresenterTests {
    @Test("outcome is blocked when the receipt failed or the trigger signals a block")
    func outcomeBlocked() {
        #expect(
            ReceiptContentPresenter.outcome(trigger: "operator.run", isSuccess: false, details: [:]) == .blocked
        )
        #expect(
            ReceiptContentPresenter.outcome(trigger: "policy.blocked", isSuccess: true, details: [:]) == .blocked
        )
    }

    @Test("outcome is no-op when an outcome field reports no change")
    func outcomeNoOp() {
        let details: [String: ReceiptJSONValue] = ["changeType": .string("no-op")]
        #expect(
            ReceiptContentPresenter.outcome(trigger: "operator.run", isSuccess: true, details: details) == .noOp
        )
    }

    @Test("outcome is artifact-producing when the payload references an artifact UUID")
    func outcomeArtifactProducing() {
        let id = UUID()
        let details: [String: ReceiptJSONValue] = ["artifactID": .string(id.uuidString)]
        #expect(
            ReceiptContentPresenter.outcome(trigger: "operator.run", isSuccess: true, details: details)
                == .artifactProducing
        )
    }

    @Test("outcome is draft-only from a camelCase draft key, which the app path previously missed")
    func outcomeDraftOnly() {
        let details: [String: ReceiptJSONValue] = ["receiptDraft": .string("prepared")]
        #expect(
            ReceiptContentPresenter.outcome(trigger: "operator.run", isSuccess: true, details: details) == .draftOnly
        )
    }

    @Test("categories are matched consistently across camelCase and snake_case keys")
    func categoryNormalizesKeyStyles() {
        #expect(ReceiptContentPresenter.category(forKey: "requestedIntent") == .intent)
        #expect(ReceiptContentPresenter.category(forKey: "interpreted_plan") == .plan)
        #expect(ReceiptContentPresenter.category(forKey: "policyReason") == .policy)
        #expect(ReceiptContentPresenter.category(forKey: "blockedReason") == .policy)
        #expect(ReceiptContentPresenter.category(forKey: "failureDetail") == .failure)
        #expect(ReceiptContentPresenter.category(forKey: "capability") == .capability)
        #expect(ReceiptContentPresenter.category(forKey: "unlabeledField") == .additional)
    }

    @Test("change rows prefer explicit change fields, then artifacts, then outcome fallbacks")
    func changeRowsPrecedence() {
        let explicit = ReceiptContentPresenter.changeRows(
            trigger: "operator.run",
            isSuccess: true,
            details: ["changedFields": .string("balance")]
        )
        #expect(explicit.map(\.value) == ["balance"])

        let id = UUID()
        let artifact = ReceiptContentPresenter.changeRows(
            trigger: "operator.run",
            isSuccess: true,
            details: ["artifactID": .string(id.uuidString)]
        )
        #expect(artifact.first?.label == "Artifact")
        #expect(artifact.first?.value == "Created or updated \(id.uuidString)")

        let draft = ReceiptContentPresenter.changeRows(
            trigger: "draft.prepare",
            isSuccess: true,
            details: [:]
        )
        #expect(draft.first?.label == "Draft")

        let blocked = ReceiptContentPresenter.changeRows(
            trigger: "policy.blocked",
            isSuccess: false,
            details: ["failureReason": .string("Insufficient authority")]
        )
        #expect(blocked.first?.label == "Stopped")
        #expect(blocked.first?.value == "Insufficient authority")
    }

    /// `outcome(trigger:isSuccess:details:)` tests the no-change marker *before* it tests for
    /// artifact IDs, so a receipt that explicitly says it changed nothing is `.noOp` even when it
    /// still carries an artifact reference. `changeRows` used to render artifacts from an early
    /// return placed above the switch, which bypassed that precedence and reported "Created or
    /// updated …" for a receipt classified as no-change. One classifier, one answer.
    @Test("an explicit no-change receipt carrying an artifact ID reports no change, not an artifact")
    func changeRowsHonourNoChangePrecedenceOverArtifactIDs() {
        // `outcome`, not `changeType`: both are no-change markers to
        // `outcome(trigger:isSuccess:details:)`, but `changeType` contains "change" and so is
        // claimed by the explicit-change-fields pass before the switch is ever reached. This test
        // is about the switch.
        let details: [String: ReceiptJSONValue] = [
            "artifactID": .string(UUID().uuidString),
            "outcome": .string("no_change")
        ]

        #expect(ReceiptContentPresenter.outcome(trigger: "operator.run", isSuccess: true, details: details) == .noOp)

        let rows = ReceiptContentPresenter.changeRows(
            trigger: "operator.run",
            isSuccess: true,
            details: details
        )
        #expect(rows.map(\.label) == ["Change"])
        #expect(rows.first?.value == "No persisted artifact or draft change was recorded.")
    }

    @Test("artifact IDs are collected only under artifact-scoped key paths, de-duplicated")
    func artifactIDExtraction() {
        let primary = UUID()
        let nested = UUID()
        let unrelated = UUID()
        let details: [String: ReceiptJSONValue] = [
            "artifactID": .string(primary.uuidString),
            "artifacts": .array([.string(primary.uuidString), .object(["id": .string(nested.uuidString)])]),
            "sessionID": .string(unrelated.uuidString)
        ]

        let ids = ReceiptContentPresenter.artifactIDs(in: details)
        #expect(Set(ids) == [primary, nested])
        #expect(ids.count == 2)
    }

    @Test("humanizeKey turns identifiers into readable labels")
    func humanizeKey() {
        #expect(ReceiptContentPresenter.humanizeKey("interpretedPlan") == "Interpreted Plan")
        #expect(ReceiptContentPresenter.humanizeKey("policy_reason") == "Policy Reason")
    }

    /// `categorizedRows` carries `sourceKey` into row identity precisely because `humanizeKey` is
    /// lossy; `changeRows` built its explicit rows without one, so two keys that humanize to the same
    /// label with equal values collided. `ReceiptDetailView` renders these with
    /// `ForEach(presentation.changeRows)`, so the collision silently dropped a row from the "what
    /// changed" summary — an audit surface under-reporting a change it had recorded.
    @Test("colliding change-row labels keep distinct identities so neither row is dropped")
    func changeRowsKeepDistinctIdentities() {
        let rows = ReceiptContentPresenter.changeRows(
            trigger: "operator.run",
            isSuccess: true,
            details: [
                "changed_by": .string("policy"),
                "changedBy": .string("policy")
            ]
        )

        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.label == "Changed By" })
        #expect(Set(rows.map(\.id)).count == 2, "both change rows must survive ForEach identity")
    }

    /// `Array.sorted` is not stable, so label-only comparison left rows with equal labels mutually
    /// unordered and free to swap between identical renders of the same receipt.
    @Test("rows with identical labels sort deterministically")
    func rowOrderingIsDeterministic() {
        let details: [String: ReceiptJSONValue] = [
            "policy_reason": .string("blocked"),
            "policyReason": .string("blocked")
        ]

        let first = ReceiptContentPresenter.categorizedRows(details: details)[.policy] ?? []
        for _ in 0 ..< 20 {
            #expect(ReceiptContentPresenter.categorizedRows(details: details)[.policy] ?? [] == first)
        }
        #expect(first.map(\.sourceKey) == ["policyReason", "policy_reason"])
    }
}

/// The canonical cross-surface view model. Covered here because both the Receipts tab and Mission
/// Control build their views from it, so a change in section selection, ordering, or searchable text
/// moves both surfaces at once.
@Suite("Receipt presentation")
struct ReceiptPresentationTests {
    private func presentation(
        trigger: String = "operator.run",
        isSuccess: Bool = true,
        correlationID: String? = "corr-1",
        details: [String: ReceiptJSONValue]
    ) -> ReceiptPresentation {
        ReceiptPresentation(
            summary: "Rebalanced the ledger",
            trigger: trigger,
            scope: "operators",
            actor: "system",
            mode: "observe",
            provenance: "local",
            correlationID: correlationID,
            isSuccess: isSuccess,
            details: details
        )
    }

    @Test("only non-empty sections appear, in canonical presentation order")
    func sectionsAreNonEmptyAndCanonicallyOrdered() {
        let result = presentation(details: [
            "requestedIntent": .string("rebalance"),
            "interpretedPlan": .string("swap"),
            "policyReason": .string("within standing policy")
        ])

        let categories = result.sections.map(\.category)
        #expect(categories == [.intent, .plan, .policy])
        #expect(result.sections.allSatisfy { !$0.rows.isEmpty })
        // Section identity is the category, so a surface cannot render two sections under one id.
        #expect(Set(result.sections.map(\.id)).count == result.sections.count)
        #expect(result.sections.map(\.title) == ["Requested Intent", "Interpreted Plan", "Policy Reasons"])
    }

    /// Receipt search runs over this string, so anything a person can see must be in it. A section
    /// title or row value missing here is a receipt that cannot be found by the words it displays.
    @Test("searchable text covers the header, every section title, and every rendered row")
    func searchableTextCoversRenderedContent() {
        let result = presentation(details: ["requestedIntent": .string("rebalance the vault")])

        for expected in [
            "Rebalanced the ledger",
            "operator.run",
            "operators",
            "system",
            "observe",
            "local",
            "corr-1",
            "Requested Intent",
            "rebalance the vault"
        ] {
            #expect(result.searchableText.contains(expected), "missing \(expected)")
        }
        #expect(result.searchableText.contains(result.outcome.rawValue))
    }

    @Test("a nil correlation id contributes nothing rather than the word nil")
    func nilCorrelationIDIsNotStringified() {
        let result = presentation(correlationID: nil, details: [:])
        #expect(!result.searchableText.contains("nil"))
    }

    @Test("outcome, change rows, and artifact ids match the presenter they delegate to")
    func projectionsMatchThePresenter() {
        let artifactID = UUID()
        let details: [String: ReceiptJSONValue] = ["artifactID": .string(artifactID.uuidString)]
        let result = presentation(details: details)

        #expect(result.outcome == .artifactProducing)
        #expect(result.artifactIDs == [artifactID])
        #expect(
            result.changeRows == ReceiptContentPresenter.changeRows(
                trigger: "operator.run",
                isSuccess: true,
                details: details
            )
        )
    }

    /// A failed receipt must not present as a quiet no-op, and its reason has to reach the summary.
    @Test("a blocked receipt surfaces its stop reason")
    func blockedReceiptSurfacesItsReason() {
        let result = presentation(
            isSuccess: false,
            details: ["policyReason": .string("Observe mode blocks signing.")]
        )

        #expect(result.outcome == .blocked)
        #expect(result.changeRows.first?.label == "Stopped")
        #expect(result.changeRows.first?.value == "Observe mode blocks signing.")
    }
}
