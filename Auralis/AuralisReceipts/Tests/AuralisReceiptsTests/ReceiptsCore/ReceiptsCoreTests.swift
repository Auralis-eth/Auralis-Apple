import Foundation
import AuralisReceipts
import Testing

struct ReceiptsCoreTests {
    @Test("receipt draft preserves append contract fields")
    func receiptDraftPreservesFields() {
        let createdAt = Date(timeIntervalSince1970: 1_704_067_200)
        let payload = ReceiptPayload(values: ["kind": .string("fixture")])

        let draft = ReceiptDraft(
            createdAt: createdAt,
            actorDetail: .human,
            authorityDetail: .humanApproval(capability: "tests.append"),
            mode: .observe,
            trigger: "test.trigger",
            scope: "tests",
            summary: "Test receipt",
            provenance: "unit-test",
            isSuccess: true,
            correlationID: "corr-1",
            timelineAccountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            timelineChainRawValue: "eth-mainnet",
            details: payload
        )

        #expect(draft.createdAt == createdAt)
        // Derived from `actorDetail`, not passed beside it — see `coarseActorIsDerivedFromActorDetail`.
        #expect(draft.actor == .user)
        #expect(draft.actorDetail == .human)
        #expect(draft.authorityDetail == .humanApproval(capability: "tests.append"))
        #expect(draft.trigger == "test.trigger")
        #expect(draft.scope == "tests")
        #expect(draft.correlationID == "corr-1")
        #expect(draft.details == payload)
    }

    /// A `nil` correlation id must survive as `nil`. Substituting a generated UUID would file the
    /// receipt under a workflow run no session or caller holds — `receipts(forCorrelationID:)` could
    /// never retrieve it, and because the value is folded into the chain hash the fabrication would
    /// be permanent. It would also break determinism: two drafts from identical inputs would differ.
    @Test("an un-correlated draft keeps a nil correlation id instead of inventing one")
    func unCorrelatedDraftKeepsNilCorrelationID() {
        func draft(correlationID: String?) -> ReceiptDraft {
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 1_704_067_200),
                actorDetail: .human,
                authorityDetail: .policyDefault(capability: "tests.append", reason: "standing policy"),
                trigger: "policy.denied",
                scope: "tests",
                summary: "Standing-policy denial",
                provenance: "unit-test",
                isSuccess: false,
                correlationID: correlationID,
                details: ReceiptPayload(values: [:])
            )
        }

        #expect(draft(correlationID: nil).correlationID == nil)
        // An empty string normalizes to nil so "" and nil cannot hash differently while meaning
        // the same thing.
        #expect(draft(correlationID: "").correlationID == nil)
        #expect(draft(correlationID: "corr-1").correlationID == "corr-1")
        // Determinism: identical inputs must compare equal.
        #expect(draft(correlationID: nil) == draft(correlationID: nil))
    }

    /// `RawReceiptPayload.fields` is an array that never deduplicates, and writers build it by
    /// conditional `append`. A duplicate key used to trap in `Dictionary(uniqueKeysWithValues:)`,
    /// crashing the app on the one path that must never take the process down.
    @Test("a duplicate payload key resolves last-wins instead of trapping")
    func duplicatePayloadKeyDoesNotTrap() {
        let payload = RawReceiptPayload(fields: [
            .public("label", string: "First", kind: .label),
            .public("label", string: "Second", kind: .label)
        ])

        let sanitized = DefaultReceiptPayloadSanitizer().sanitize(payload)

        #expect(sanitized.values["label"] == .string("Second"))
        #expect(sanitized.values.count == 1)
    }

    @Test("payload sanitizer keeps public labels and redacts error and opaque-token fields")
    func sanitizerKeepsLabelsAndRedactsSensitiveKinds() {
        let payload = RawReceiptPayload(fields: [
            .public("label", string: "Visible Label", kind: .label),
            .public("error", string: "request failed with provider details", kind: .errorMessage),
            .redacted("token", string: "secret-token-value", kind: .opaqueToken)
        ])

        let sanitized = DefaultReceiptPayloadSanitizer().sanitize(payload)

        #expect(sanitized.values["label"] == .string("Visible Label"))
        #expect(sanitized.values["error"] == .string("<redacted-error>"))
        #expect(sanitized.values["token"] == .string("<redacted-opaque-token>"))
    }

    /// `stringArray` accepted `kind:` and threw it away, so the sanitizer classified each element
    /// against the parent's `.array` kind — not a string kind — and replaced every element with
    /// `<redacted-unexpected-string>`. Two live writers were affected: a music receipt's
    /// `affectedMediaIDs` and a context receipt's `selectedChains`. Both fields exist *only* to
    /// record which items an action touched, so the receipt asserted a fact it had not stored.
    @Test("string array elements sanitize by their declared element kind, not as arrays")
    func stringArrayElementsUseDeclaredElementKind() {
        let payload = RawReceiptPayload(fields: [
            .stringArray("affectedMediaIDs", values: ["track-1", "track-2"], kind: .label),
            .stringArray("selectedChains", values: ["ethereum", "base"], kind: .chain)
        ])

        let sanitized = DefaultReceiptPayloadSanitizer().sanitize(payload)

        #expect(sanitized.values["affectedMediaIDs"] == .array([.string("track-1"), .string("track-2")]))
        #expect(sanitized.values["selectedChains"] == .array([.string("ethereum"), .string("base")]))
    }

    /// The element kind is a hint about shape, never a licence to publish. A suspicious *key* still
    /// redacts every element, and a per-element classification still fires — otherwise declaring
    /// `kind: .label` would have become a way to launder secrets into a receipt.
    @Test("a sensitive key and per-element classification still redact array elements")
    func stringArrayElementsStillRedactWhenWarranted() {
        let payload = RawReceiptPayload(fields: [
            .stringArray("apiKeys", values: ["abc", "def"], kind: .label),
            .stringArray("endpoints", values: ["https://example.com/v1/path?key=abc"], kind: .label)
        ])

        let sanitized = DefaultReceiptPayloadSanitizer().sanitize(payload)

        #expect(sanitized.values["apiKeys"] == .array([.string("<redacted-label>"), .string("<redacted-label>")]))
        // Classified as a URL on its content despite the declared `.label`, so it is structurally
        // reduced rather than published with its query string.
        #expect(
            sanitized.values["endpoints"]
                == .array([.string("https://example.com/<redacted-path>?<redacted-query>")])
        )
    }

    /// The opaque-token heuristic (`count >= 24` of `[A-Za-z0-9_-]`) was tested *before* the
    /// structured forms, so it swallowed every explicitly declared kind whose value happened to be
    /// 24 characters or longer — which a 42-character `0x…` address always is. A declared
    /// `.walletAddress` therefore persisted as the constant `<redacted-opaque-token>`: a spend
    /// receipt could not name its recipient, and two spends to two different addresses recorded
    /// byte-identical identity fields.
    @Test("a declared wallet address is not swallowed by the opaque-token heuristic")
    func declaredWalletAddressSurvivesSanitization() {
        // The canonical EIP-55 checksummed fixtures, so the mixed case is exercised too.
        let recipient = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
        let otherRecipient = "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359"

        let sanitized = DefaultReceiptPayloadSanitizer().sanitize(
            RawReceiptPayload(fields: [
                .public("recipientAddress", string: recipient, kind: .walletAddress),
                .hashed("counterparty", string: recipient, kind: .walletAddress),
                .hashed("otherCounterparty", string: otherRecipient, kind: .walletAddress)
            ])
        )

        // Masked on the public path, which is what `.walletAddress` means — not replaced wholesale.
        #expect(sanitized.values["recipientAddress"] == .string("0x5aAe…eAed"))
        // On the hashed path the digest is per-address, so the receipt still distinguishes who was
        // paid. Collapsing both to one placeholder is what made two different spends identical.
        #expect(sanitized.values["counterparty"] != sanitized.values["otherCounterparty"])
        for key in ["counterparty", "otherCounterparty"] {
            guard case .string(let value)? = sanitized.values[key] else {
                Issue.record("Expected a sanitized string for \(key).")
                return
            }
            #expect(value.hasPrefix("sha256:"))
        }
    }

    /// Same defect, the other fixed-length form: a 36-character UUID string also satisfies the
    /// opaque-token heuristic, so a declared `.label` holding one persisted as
    /// `<redacted-opaque-token>` — two different playlists produced identical receipts, and
    /// ``ReceiptContentPresenter/artifactIDs(in:)`` found nothing to link to because the UUIDs were
    /// gone by the time it read the payload back.
    @Test("a declared label holding a UUID is not swallowed by the opaque-token heuristic")
    func declaredUUIDLabelSurvivesSanitization() {
        let playlistID = UUID()
        let otherPlaylistID = UUID()
        let artifactID = UUID()

        let sanitized = DefaultReceiptPayloadSanitizer().sanitize(
            RawReceiptPayload(fields: [
                .public("playlistID", string: playlistID.uuidString, kind: .label),
                .public("otherPlaylistID", string: otherPlaylistID.uuidString, kind: .label),
                .public("artifactID", string: artifactID.uuidString, kind: .label)
            ])
        )

        #expect(sanitized.values["playlistID"] == .string(playlistID.uuidString))
        #expect(sanitized.values["otherPlaylistID"] == .string(otherPlaylistID.uuidString))
        // End to end: the artifact link a receipt exists to carry is recoverable from what was
        // actually persisted, by the same parser the sanitizer exempts.
        #expect(ReceiptContentPresenter.artifactIDs(in: sanitized.values) == [artifactID])
    }

    /// A key inside an `.object` carries no declared kind, so it is classified by
    /// `inferredValueKind(forKey:value:)` from the key alone. The UUID exemption applies there
    /// too, because otherwise the same receipt disagrees with itself: `MusicReceiptStateSummary`
    /// records `playlistID` both as a top-level field and inside its before/after summaries, and
    /// only the top-level one survived.
    @Test("a UUID nested inside an object survives, so before/after summaries name the same thing")
    func nestedUUIDSurvivesSanitization() {
        let playlistID = UUID()
        let sanitized = DefaultReceiptPayloadSanitizer().sanitize(
            RawReceiptPayload(fields: [
                ReceiptPayloadField(
                    key: "beforeSummary",
                    value: .object(["playlistID": .string(playlistID.uuidString), "itemCount": .number(1)]),
                    sensitivity: .public,
                    valueKind: .object
                ),
                ReceiptPayloadField(
                    key: "playlistID",
                    value: .string(playlistID.uuidString),
                    sensitivity: .public,
                    valueKind: .label
                )
            ])
        )

        #expect(
            sanitized.values["beforeSummary"]
                == .object(["playlistID": .string(playlistID.uuidString), "itemCount": .number(1)])
        )
        // The point of the widening: the nested copy and the top-level field agree.
        guard case .object(let summary)? = sanitized.values["beforeSummary"] else {
            Issue.record("Expected beforeSummary to stay an object")
            return
        }
        #expect(summary["playlistID"] == sanitized.values["playlistID"])
    }

    /// Widening the *kind* must not widen the *sensitivity*.
    /// `resolvedSensitivity(for:kind:stringValue:)` tests `keyLooksSensitive(field.key)` before it
    /// looks at the kind, so a UUID-shaped credential under a key that names one is still redacted
    /// — which is what makes the exemption safe to apply to undeclared keys at all.
    @Test("a nested UUID under a sensitive key is still redacted on the strength of its key")
    func nestedUUIDUnderASensitiveKeyStillRedacts() {
        let sanitized = DefaultReceiptPayloadSanitizer().sanitize(
            RawReceiptPayload(fields: [
                ReceiptPayloadField(
                    key: "afterSummary",
                    value: .object([
                        "apiKey": .string(UUID().uuidString),
                        "authToken": .string(UUID().uuidString),
                        "sessionSecret": .string(UUID().uuidString)
                    ]),
                    sensitivity: .public,
                    valueKind: .object
                )
            ])
        )

        guard case .object(let summary)? = sanitized.values["afterSummary"] else {
            Issue.record("Expected afterSummary to stay an object")
            return
        }
        for key in ["apiKey", "authToken", "sessionSecret"] {
            guard case .string(let value)? = summary[key] else {
                Issue.record("Expected \(key) to sanitize to a string")
                return
            }
            #expect(value.hasPrefix("<redacted-"), "\(key) leaked a UUID-shaped credential: \(value)")
        }
    }

    /// The heuristic remains the defence for nested values that are *not* UUID-shaped, so an
    /// arbitrary 24+ character run inside an object is still caught.
    @Test("a nested arbitrary token-shaped string is still classified as an opaque token")
    func nestedArbitraryTokenStillRedacts() {
        let sanitized = DefaultReceiptPayloadSanitizer().sanitize(
            RawReceiptPayload(fields: [
                ReceiptPayloadField(
                    key: "afterSummary",
                    value: .object(["handoff": .string("opaqueFixtureTokenABCDEF0123456789")]),
                    sensitivity: .public,
                    valueKind: .object
                )
            ])
        )

        #expect(sanitized.values["afterSummary"] == .object(["handoff": .string("<redacted-opaque-token>")]))
    }

    /// The heuristic is the anti-laundering defence for everything that is *not* one of those two
    /// fixed-length shapes, so an arbitrary 24+ character run must still be caught — otherwise
    /// declaring `kind: .label` would be a way to publish a bearer token into a receipt.
    @Test("an arbitrary long token-shaped string is still classified as an opaque token")
    func arbitraryLongStringsStillRedactAsOpaqueTokens() {
        let sanitized = DefaultReceiptPayloadSanitizer().sanitize(
            RawReceiptPayload(fields: [
                .public("sessionHandle", string: "opaqueFixtureTokenZYXWVU9876543210", kind: .label)
            ])
        )

        #expect(sanitized.values["sessionHandle"] == .string("<redacted-opaque-token>"))
    }

    @Test("hashed freeform payload fields produce a stable sha256 digest")
    func hashedFreeformFieldsAreDeterministic() {
        let field = ReceiptPayloadField.hashed("safeHash", string: "stable input value", kind: .freeformText)
        let payload = RawReceiptPayload(fields: [field])

        let first = DefaultReceiptPayloadSanitizer().sanitize(payload)
        let second = DefaultReceiptPayloadSanitizer().sanitize(payload)

        #expect(first.values["safeHash"] == second.values["safeHash"])
        guard case .string(let hash) = first.values["safeHash"] else {
            Issue.record("Expected hashed string value.")
            return
        }
        #expect(hash.hasPrefix("sha256:"))
        #expect(hash.count == 71)
    }

    /// `actor` is persisted as the filterable column *and* committed to the integrity chain as
    /// `actorRawValue`, so a disagreement with `actorDetail` is unfalsifiable once written. While
    /// `actor:` was a defaulted parameter beside a required `actorDetail`, the shape that produced
    /// one was the ordinary one — `ReceiptDraft(actorDetail: .human, …)` with `actor:` omitted gave
    /// `actor == .system` next to `actorDetail == .human`. Writers could also pass a third answer
    /// agreeing with neither. There is no `actor:` parameter now, so the two cannot diverge.
    @Test("the coarse actor column is derived from the structured detail, not set beside it")
    func coarseActorIsDerivedFromActorDetail() {
        func draft(actorDetail: ReceiptActorDetail) -> ReceiptDraft {
            ReceiptDraft(
                actorDetail: actorDetail,
                authorityDetail: nil,
                trigger: "tests.attribution",
                scope: "tests",
                summary: "Attribution fixture",
                provenance: "unit-test",
                isSuccess: true,
                correlationID: "corr-attribution",
                details: ReceiptPayload(values: [:])
            )
        }

        #expect(draft(actorDetail: .human).actor == .user)
        #expect(draft(actorDetail: .workflow("nft.refresh")).actor == .system)
        #expect(draft(actorDetail: .operatorPack("ledger")).actor == .system)
        // The convenience initializer reaches the same place, so neither entry point can drift.
        let convenience = ReceiptDraft(
            category: "tests",
            kind: "tests.attribution",
            correlationID: "corr-attribution",
            payload: ReceiptPayload(values: [:]),
            actorDetail: .human,
            authorityDetail: nil
        )
        #expect(convenience.actor == .user)
        #expect(convenience.actor == convenience.actorDetail?.coarseActor)
    }
}

@Suite("Inference provenance presentation (P1-AI-102/103)")
struct ReceiptInferencePresentationTests {
    private func telemetryDetails(locality: String) -> [String: ReceiptJSONValue] {
        [
            "modelProvider": .string("Apple Foundation Models"),
            "modelClass": .string("local-language-model"),
            "inferenceLocality": .string(locality),
            "promptTokens": .string("120"),
            "completionTokens": .string("48"),
            "tokensEstimated": .string("false"),
            "estimatedCost": .string("0.0"),
            "stepTitle": .string("Summarize findings")
        ]
    }

    @Test("inference telemetry keys land in the AI Provenance section, not Additional Details")
    func telemetryKeysCategorizeAsInference() {
        let rows = ReceiptContentPresenter.categorizedRows(details: telemetryDetails(locality: "local"))
        let inferenceLabels = Set((rows[.inference] ?? []).map(\.label))

        #expect(inferenceLabels.contains("Model Provider"))
        #expect(inferenceLabels.contains("Model Class"))
        #expect(inferenceLabels.contains("Inference Locality"))
        #expect(inferenceLabels.contains("Prompt Tokens"))
        #expect(inferenceLabels.contains("Completion Tokens"))
        #expect(inferenceLabels.contains("Estimated Cost"))
        // A non-inference field still routes elsewhere.
        #expect((rows[.inference] ?? []).contains { $0.label == "Step Title" } == false)
    }

    @Test("ordinary token and duration fields are not mistaken for AI telemetry")
    func nonInferenceFieldsStayOutOfInferenceSection() {
        let rows = ReceiptContentPresenter.categorizedRows(details: [
            "tokenAddress": .string("0x1234"),
            "duration": .string("3 days")
        ])

        #expect(rows[.inference] == nil)
        let additionalLabels = Set((rows[.additional] ?? []).map(\.label))
        #expect(additionalLabels == ["Duration", "Token Address"])
    }

    @Test("local inference synthesizes an on-device privacy impact row")
    func localPrivacyImpactRow() {
        let rows = ReceiptContentPresenter.categorizedRows(details: telemetryDetails(locality: "local"))
        let impact = (rows[.inference] ?? []).first { $0.label == "Privacy impact" }
        #expect(impact?.value == "On-device — inputs stay on this device")
    }

    @Test("remote inference synthesizes an off-device privacy impact row")
    func remotePrivacyImpactRow() {
        let rows = ReceiptContentPresenter.categorizedRows(details: telemetryDetails(locality: "remote"))
        let impact = (rows[.inference] ?? []).first { $0.label == "Privacy impact" }
        #expect(impact?.value == "Sent to provider — inputs leave this device")
    }

    @Test("receipts without inference get no AI Provenance section")
    func noInferenceNoSection() {
        let rows = ReceiptContentPresenter.categorizedRows(details: ["summary": .string("Opened a screen")])
        #expect(rows[.inference] == nil)
    }

    /// `usesInference` must be honoured whether the writer stringified it or used the idiomatic
    /// `ReceiptPayloadField.bool(_:_:)`. Reading only `.string` defaulted the boolean form to `true`,
    /// framing a deterministic on-chain data read as AI inference and synthesizing a privacy row.
    @Test("usesInference is honoured as a bool as well as a string", arguments: [
        ReceiptJSONValue.bool(false),
        ReceiptJSONValue.string("false")
    ])
    func usesInferenceAcceptsBothEncodings(flag: ReceiptJSONValue) {
        var details = telemetryDetails(locality: "local")
        details["usesInference"] = flag

        let rows = ReceiptContentPresenter.categorizedRows(details: details)

        #expect(rows[.inference] == nil, "a deterministic data read must not get an AI Provenance section")
        // The route stays visible for provenance, just not as inference.
        let additionalLabels = Set((rows[.additional] ?? []).map(\.label))
        #expect(additionalLabels.contains("Model Provider"))
        // Never rendered as a row — it is internal plumbing.
        #expect(rows.values.flatMap { $0 }.contains { $0.label.lowercased().contains("uses inference") } == false)
    }

    /// The "Privacy impact" row is derived from `inferenceLocality` so it can never contradict the
    /// locality it came from — but a stored `privacyImpact` used to short-circuit the derivation and
    /// render in its place. `.label` is `.public`, so the sanitizer passes such a value through
    /// untouched: a receipt recording `inferenceLocality: "remote"` displayed "On-device — inputs
    /// stay on this device" for inference that left the device. The `privacy_impact` spelling hit
    /// the secondary shape of the same defect, rendering a stored row *and* the derived row side by
    /// side in one section, disagreeing.
    @Test("a stored privacy impact cannot contradict the recorded inference locality", arguments: [
        "privacyImpact",
        "privacy_impact"
    ])
    func storedPrivacyImpactNeverOverridesTheDerivedRow(key: String) {
        var details = telemetryDetails(locality: "remote")
        details[key] = .string("On-device — inputs stay on this device")

        let rows = ReceiptContentPresenter.categorizedRows(details: details)
        let impactRows = (rows[.inference] ?? []).filter { $0.label.lowercased() == "privacy impact" }

        #expect(impactRows.count == 1, "exactly one privacy-impact row, and it must be the derived one")
        #expect(impactRows.first?.value == "Sent to provider — inputs leave this device")
        // Not relocated into another section either — the stored claim must not be renderable at all.
        #expect(rows.values.flatMap { $0 }.contains { $0.value.contains("On-device") } == false)
    }

    /// `humanizeKey` is lossy: `policy_reason` and `policyReason` both render "Policy Reason". With
    /// identity as label+value alone, two such keys with equal values collided and `ForEach` silently
    /// dropped a row.
    @Test("two payload keys that humanize to the same label keep distinct row identities")
    func collidingLabelsKeepDistinctIdentities() {
        let rows = ReceiptContentPresenter.categorizedRows(details: [
            "policy_reason": .string("blocked"),
            "policyReason": .string("blocked")
        ])

        let allRows = rows.values.flatMap { $0 }
        let colliding = allRows.filter { $0.label == "Policy Reason" }
        #expect(colliding.count == 2)
        #expect(Set(colliding.map(\.id)).count == 2, "row identities must stay unique")
    }

    @Test("AI Provenance has a stable title and ordering slot shared across surfaces")
    func inferenceSectionTitleAndOrder() {
        #expect(ReceiptContentCategory.inference.displayTitle == "AI Provenance")
        let order = ReceiptContentCategory.presentationOrder
        guard let action = order.firstIndex(of: .action),
              let inference = order.firstIndex(of: .inference),
              let output = order.firstIndex(of: .output) else {
            Issue.record("Expected action/inference/output in presentation order.")
            return
        }
        #expect(action < inference)
        #expect(inference < output)
    }

    @Test("full presentation surfaces the AI Provenance section end-to-end")
    func presentationIncludesInferenceSection() {
        let presentation = ReceiptPresentation(
            summary: "Autopilot step",
            trigger: "autopilot.step.ran",
            scope: "autopilot",
            actor: "system",
            mode: "observe",
            provenance: "autopilot",
            correlationID: "corr-1",
            isSuccess: true,
            details: telemetryDetails(locality: "local")
        )
        let section = presentation.sections.first { $0.category == .inference }
        #expect(section != nil)
        #expect(section?.rows.contains { $0.label == "Privacy impact" } == true)
    }
}
