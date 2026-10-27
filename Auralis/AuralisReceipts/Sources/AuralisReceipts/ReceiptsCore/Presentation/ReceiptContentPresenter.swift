import Foundation

/// Compact postflight classification of a completed receipt. (P1-303)
///
/// This is the single source of truth for how any Auralis surface interprets a receipt payload.
/// UI layers map it onto their own display types (titles, icons, colors).
public enum ReceiptOutcomeKind: String, Sendable, CaseIterable {
    case noOp
    case draftOnly
    case artifactProducing
    case blocked
}

/// Semantic grouping for a single receipt-detail field. (P1-301/302)
public enum ReceiptContentCategory: String, Sendable, CaseIterable {
    case intent
    case plan
    case approval
    case action
    /// Local-vs-remote inference provenance and telemetry: which model/provider ran, on- or
    /// off-device, its token usage, estimated cost, and the derived privacy impact. (P1-AI-102/103)
    case inference
    case output
    case policy
    case failure
    case capability
    case additional
}

/// A humanized label/value pair derived from a receipt payload field.
public struct ReceiptContentRow: Identifiable, Equatable, Sendable {
    public let label: String
    public let value: String
    /// The payload key this row was derived from, folded into ``id`` only.
    ///
    /// `humanizeKey` is lossy — `policy_reason` and `policyReason` both render "Policy Reason" — so
    /// label+value alone is not unique within a section. Two such keys with equal values would give
    /// `ForEach` duplicate identities and silently drop a row. Not part of `Equatable` display
    /// semantics beyond identity, and defaulted so existing callers are unaffected.
    public let sourceKey: String

    public init(label: String, value: String, sourceKey: String = "") {
        self.label = label
        self.value = value
        self.sourceKey = sourceKey
    }

    public var id: String { "\(sourceKey)\u{1F}\(label)\u{1F}\(value)" }
}

/// The one place that turns a raw receipt payload into human-readable, categorized content,
/// its postflight outcome, and the "what changed" summary.
///
/// Both the standalone Receipts tab (`Auralis/Receipts/*`) and the Mission Control console
/// (`AuralisMissionControl`) delegate here so their receipt presentation can never drift.
public enum ReceiptContentPresenter {
    // MARK: Postflight outcome (P1-303)

    public static func outcome(
        trigger: String,
        isSuccess: Bool,
        details: [String: ReceiptJSONValue]
    ) -> ReceiptOutcomeKind {
        let normalizedTrigger = trigger.lowercased()

        if !isSuccess || normalizedTrigger.contains("blocked") || normalizedTrigger.contains("failed") {
            return .blocked
        }
        if stringValue(forAnyOf: ["outcome", "result", "changeType"], in: details)?.isNoChangeReceiptValue == true {
            return .noOp
        }
        if !artifactIDs(in: details).isEmpty {
            return .artifactProducing
        }
        if normalizedTrigger.contains("draft")
            || details.keys.contains(where: { $0.lowercased().contains("draft") }) {
            return .draftOnly
        }

        return .noOp
    }

    // MARK: Categorized readable rows (P1-301/302)

    public static func categorizedRows(
        details: [String: ReceiptJSONValue]
    ) -> [ReceiptContentCategory: [ReceiptContentRow]] {
        // `usesInference == false` marks a deterministic local data read (e.g. the on-chain ledger
        // indexer): it carries a route for provenance but must not be framed as AI inference. Absent
        // on legacy receipts, which are treated as inference for backward compatibility. (P1-AI-103)
        let usesInference: Bool = {
            // Both spellings are accepted: the current producer stringifies it into a `[String: String]`
            // payload, but `ReceiptPayloadField.bool(_:_:)` is the idiomatic writer API, and a writer
            // using it would otherwise fall through to `true` and get a deterministic data read framed
            // as AI inference.
            switch details["usesInference"] {
            case let .string(value)?: return Bool(value) ?? true
            case let .bool(value)?: return value
            default: return true
            }
        }()

        var grouped = details.reduce(into: [ReceiptContentCategory: [ReceiptContentRow]]()) { partial, item in
            // `usesInference` is internal plumbing, not a user-facing fact — never render it as a row.
            //
            // A stored `privacyImpact` is dropped for a sharper reason: the row below is *derived*
            // from `inferenceLocality` precisely so it can never contradict the locality it came
            // from, and a payload is free to carry a `privacyImpact` that disagrees. `.label` is
            // `.public`, so the sanitizer passes it through untouched — a receipt recording
            // `inferenceLocality: "remote"` could display "On-device — inputs stay on this device"
            // for inference that left the device. Dropping it also closes the second shape of the
            // same problem, where a `privacy_impact` key rendered a stored row *and* the derived
            // row side by side in one section, disagreeing.
            //
            // Normalized through `humanizeKey` the way `category(forKey:)` normalizes, so
            // `privacyImpact` and `privacy_impact` are both caught — and `usesInference` now gets
            // `uses_inference` for free, which the old raw-lowercase compare missed.
            let normalizedKey = humanizeKey(item.key).lowercased()
            guard normalizedKey != "uses inference", normalizedKey != "privacy impact" else { return }
            let row = ReceiptContentRow(
                label: humanizeKey(item.key),
                value: describe(item.value),
                sourceKey: item.key
            )
            var category = category(forKey: item.key)
            // For a non-inference data read, keep the provenance visible but out of the AI Provenance
            // section so it never reads as "a model ran".
            if !usesInference, category == .inference {
                category = .additional
            }
            partial[category, default: []].append(row)
        }

        // Synthesize the trust-facing "Privacy impact" row from the recorded inference locality
        // (P1-AI-102). Derived, never stored, so it can never contradict the locality it came from.
        // Only for real inference — a local data read gets no AI-provenance framing.
        if usesInference, let impact = privacyImpactRow(details: details) {
            grouped[.inference, default: []].append(impact)
        }

        return grouped.mapValues { rows in
            rows.sorted(by: isOrderedBefore)
        }
    }

    /// A *total* order over rows, because `humanizeKey` is lossy and `Array.sorted` is not stable.
    ///
    /// `policy_reason` and `policyReason` produce two rows with the same label, and comparing labels
    /// alone makes them mutually unordered — so their relative position is whatever the sort happens
    /// to do with that bucket, and a receipt could render its rows in a different order on each pass.
    /// `sourceKey` is unique within a payload (it is a dictionary key), so it breaks every tie.
    private static func isOrderedBefore(_ lhs: ReceiptContentRow, _ rhs: ReceiptContentRow) -> Bool {
        (lhs.label, lhs.sourceKey) < (rhs.label, rhs.sourceKey)
    }

    public static func category(forKey key: String) -> ReceiptContentCategory {
        // Normalize camelCase and snake_case uniformly so "receiptDraft" and "receipt_draft" match alike.
        let normalized = humanizeKey(key).lowercased()

        // Inference provenance/telemetry keys (modelProvider, modelClass, inferenceLocality,
        // prompt/completionTokens, tokensEstimated, estimatedCost). Checked first so trust-critical
        // fields land in their own section rather than being scooped up by a broader rule below
        // (e.g. "estimatedCost" would otherwise fall through to Additional).
        let inferenceKeys: Set<String> = [
            "inference locality",
            "model provider",
            "model class",
            "prompt tokens",
            "completion tokens",
            "tokens estimated",
            "duration seconds",
            "inference duration",
            "inference duration milliseconds",
            "estimated cost",
            "privacy impact"
        ]
        if inferenceKeys.contains(normalized) {
            return .inference
        }
        if normalized.contains("intent") || normalized.contains("request") || normalized == "goal" {
            return .intent
        }
        if normalized.contains("plan") || normalized.contains("step") {
            return .plan
        }
        if normalized.contains("approval") || normalized.contains("confirmation") {
            return .approval
        }
        if normalized.contains("capability") || normalized.contains("permission") || normalized.contains("power") {
            return .capability
        }
        if normalized.contains("policy") || normalized.contains("reason") || normalized.contains("risk") || normalized.contains("impact") {
            return .policy
        }
        if normalized.contains("error") || normalized.contains("failure") || normalized.contains("failed") || normalized.contains("blocked") || normalized.contains("denied") {
            return .failure
        }
        if normalized.contains("output") || normalized.contains("result") || normalized.contains("artifact") || normalized.contains("receipt draft") {
            return .output
        }
        if normalized.contains("action") || normalized.contains("tool") || normalized.contains("operation") || normalized.contains("execution") {
            return .action
        }

        return .additional
    }

    // MARK: Change summary (P1-303)

    public static func changeRows(
        trigger: String,
        isSuccess: Bool,
        details: [String: ReceiptJSONValue]
    ) -> [ReceiptContentRow] {
        let explicit = details
            .filter { key, _ in
                let normalized = key.lowercased()
                return normalized.contains("change")
                    || normalized.contains("changed")
                    || normalized.contains("diff")
                    || normalized == "before"
                    || normalized == "after"
            }
            // `sourceKey` for the same reason ``categorizedRows(details:)`` carries one: `humanizeKey`
            // is lossy, so `changed_by` and `changedBy` both render "Changed By". With identity as
            // label+value alone, two such keys holding equal values produce two rows with the same
            // `id`, and `ForEach(presentation.changeRows)` in `ReceiptDetailView` silently drops one —
            // a "what changed" surface under-reporting what changed.
            .map {
                ReceiptContentRow(
                    label: humanizeKey($0.key),
                    value: describe($0.value),
                    sourceKey: $0.key
                )
            }
            .sorted(by: isOrderedBefore)

        if !explicit.isEmpty {
            return explicit
        }

        // `outcome(trigger:isSuccess:details:)` is the single classifier, so the artifact case is
        // rendered from inside the switch rather than from an early return above it.
        //
        // Splitting the decision across two places had produced two defects. The switch's
        // `.artifactProducing` arm was unreachable — the early return had already handled every
        // input that reaches it — and it returned "No persisted artifact or draft change was
        // recorded.", the negation of the case it was labelled with; it would have started
        // printing that the moment `outcome()` gained any artifact signal other than a non-empty
        // `artifactIDs`. And the early return ignored `outcome()`'s own precedence: `.noOp` is
        // tested *before* `.artifactProducing` there, so a receipt explicitly marked no-change
        // that still carried artifact IDs was classified `.noOp` and nevertheless rendered
        // "Created or updated …".
        switch outcome(trigger: trigger, isSuccess: isSuccess, details: details) {
        case .artifactProducing:
            return artifactIDs(in: details).map { artifactID in
                ReceiptContentRow(label: "Artifact", value: "Created or updated \(artifactID.uuidString)")
            }
        case .draftOnly:
            return [ReceiptContentRow(label: "Draft", value: "Prepared for review; no artifact was committed.")]
        case .blocked:
            let categorized = categorizedRows(details: details)
            let reason = categorized[.failure]?.first?.value
                ?? categorized[.policy]?.first?.value
                ?? "No changes were applied."
            return [ReceiptContentRow(label: "Stopped", value: reason)]
        case .noOp:
            return [ReceiptContentRow(label: "Change", value: "No persisted artifact or draft change was recorded.")]
        }
    }

    // MARK: Artifact extraction

    /// UUIDs referenced under any "artifact"-scoped key path within the payload.
    public static func artifactIDs(in details: [String: ReceiptJSONValue]) -> [UUID] {
        var seen = Set<UUID>()
        var artifactIDs: [UUID] = []

        func append(_ id: UUID) {
            guard seen.insert(id).inserted else { return }
            artifactIDs.append(id)
        }

        func collect(value: ReceiptJSONValue, keyPath: [String]) {
            let isArtifactContext = keyPath.contains { key in
                key.lowercased().contains("artifact")
            }

            switch value {
            case .string(let rawValue):
                guard isArtifactContext, let id = UUID(uuidString: rawValue) else { return }
                append(id)
            case .array(let values):
                for value in values {
                    collect(value: value, keyPath: keyPath)
                }
            case .object(let values):
                for key in values.keys.sorted() {
                    guard let value = values[key] else { continue }
                    collect(value: value, keyPath: keyPath + [key])
                }
            case .number, .bool, .null:
                return
            }
        }

        for key in details.keys.sorted() {
            guard let value = details[key] else { continue }
            collect(value: value, keyPath: [key])
        }

        return artifactIDs
    }

    // MARK: Value rendering

    public static func describe(_ value: ReceiptJSONValue) -> String {
        switch value {
        case .string(let string):
            return string
        case .number(let number):
            return number.formatted()
        case .bool(let bool):
            return bool ? "true" : "false"
        case .null:
            return "null"
        case .array(let values):
            return values.map(describe).joined(separator: "\n")
        case .object(let values):
            return values.keys.sorted().compactMap { key in
                values[key].map { "\(humanizeKey(key)): \(describe($0))" }
            }
            .joined(separator: "\n")
        }
    }

    public static func humanizeKey(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .capitalized
    }

    // MARK: Private

    /// Builds the derived "Privacy impact" row when a receipt recorded where inference ran.
    ///
    /// Mirrors `AuralisRuntime.InferenceLocality.privacyImpact` — AuralisReceipts is a dependency-free leaf,
    /// so the tiny mapping is duplicated here rather than importing AuralisRuntime. Keep the wording in
    /// sync with that type.
    ///
    /// `inferenceLocality` is the *only* input. A stored `privacyImpact` used to short-circuit this
    /// and render in place of the derived value, which contradicted the contract stated at the call
    /// site: a payload pairing `inferenceLocality: "remote"` with an on-device privacy claim then
    /// displayed the on-device claim for inference that left the device. The stored key is dropped
    /// in ``categorizedRows(details:)`` instead, so there is nothing left to prefer.
    private static func privacyImpactRow(details: [String: ReceiptJSONValue]) -> ReceiptContentRow? {
        guard case let .string(rawLocality)? = details["inferenceLocality"] else { return nil }
        let impact: String
        switch rawLocality.lowercased() {
        case "local":
            impact = "On-device — inputs stay on this device"
        case "remote":
            impact = "Sent to provider — inputs leave this device"
        default:
            return nil
        }
        return ReceiptContentRow(label: "Privacy impact", value: impact)
    }

    private static func stringValue(
        forAnyOf keys: [String],
        in details: [String: ReceiptJSONValue]
    ) -> String? {
        for key in keys {
            if case let .string(value)? = details[key] {
                return value
            }
        }

        return nil
    }
}

private extension String {
    var isNoChangeReceiptValue: Bool {
        let normalized = lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")

        return normalized == "noop"
            || normalized == "nochange"
            || normalized == "unchanged"
    }
}
