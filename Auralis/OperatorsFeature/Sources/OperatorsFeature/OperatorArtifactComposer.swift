import Foundation
import RuntimeCore

/// The composed result of an operator run: the artifact body plus the structured signals the runtime
/// surfaces (alerts, prepared actions) and stamps onto the receipt/output fields.
public struct ComposedOperatorArtifact: Equatable, Sendable {
    public let title: String
    public let body: String
    /// How many events this composition **attributed** — not how many it observed, and not how many
    /// are findings in the ordinary sense of the word.
    ///
    /// The distinction is load-bearing because a monitoring gap (`.unobserved`) is attributed but not
    /// observed, so this count and the body's "Observed N events" legitimately disagree: a watch
    /// handed one provider timeout for a watched target renders "Observed 0 events · 1 monitoring
    /// gap." and reports `findingCount` 1. That is the intended reading — the gap *is* something the
    /// run attributed to the watchlist and something the reader needs told — and it is the invariant
    /// ``attributedSourceReceiptIDs`` is already built on, so the two stay in step by construction.
    ///
    /// Recorded here rather than changed because nothing in production reads this field — only
    /// `preparedActionCount`/`preparedActionChain`/`preparedActionAddress` cross into
    /// `MissionControlHomeModel` — so there is no escalation path that could act on the difference,
    /// and narrowing it would be a receipt-content semantics change that leaves every artifact
    /// already on disk meaning the other thing.
    public let findingCount: Int
    public let alertCount: Int
    public let preparedActions: [PreparedAction]
    /// Receipts for the events this composition actually *attributed* — the ones its body reports and
    /// its `findingCount` counts — in feed order, so the artifact's provenance links name the same
    /// evidence the artifact's prose does.
    ///
    /// This is carried out of the composer rather than re-derived by ``OperatorExecutor`` because the
    /// composer is the only thing that knows which inputs a kind kept. The executor linked
    /// `activity.compactMap(\.sourceReceiptID)` — the *whole* data-source feed — so the one record
    /// disagreed with itself: an on-chain watch handed three receipted events of which one was on the
    /// watched chain said "Observed 1 event" with `findingCount` 1, while `relatedReceiptIDs` held
    /// all three and `sourceReceiptCount` said "3", two of them pointing at another chain's activity
    /// the report excluded by design. An empty watchlist was starker still: no sections rendered, no
    /// findings, and up to 50 receipts linked anyway. Re-deriving the `(chain, address)` match in the
    /// executor would have fixed the number and planted the rule in a second place, which is the
    /// defect this file already paid for once (see `matches`).
    public let attributedSourceReceiptIDs: [UUID]

    public init(
        title: String,
        body: String,
        findingCount: Int,
        alertCount: Int,
        preparedActions: [PreparedAction],
        attributedSourceReceiptIDs: [UUID]
    ) {
        self.title = title
        self.body = body
        self.findingCount = findingCount
        self.alertCount = alertCount
        self.preparedActions = preparedActions
        self.attributedSourceReceiptIDs = attributedSourceReceiptIDs
    }
}

/// Turns real inputs (`OperatorRequest`) and real local activity (`ObservedActivity`) into a
/// structured artifact body per operator kind. Pure and deterministic, so it is unit-testable and the
/// artifact is reproducible from its receipt. (P1-701..703)
public enum OperatorArtifactComposer {
    private static let staleAfter: TimeInterval = 7 * 24 * 60 * 60

    public static func compose(
        kind: OperatorKind,
        request: OperatorRequest,
        activity: [ObservedActivity],
        now: Date
    ) -> ComposedOperatorArtifact {
        switch kind {
        case .research:
            return composeResearch(request: request, activity: activity, now: now)
        case .onChainWatch:
            return composeWatch(request: request, activity: activity, now: now)
        case .identityReview:
            return composeIdentityReview(request: request, activity: activity, now: now)
        case .preparedAction:
            return composePreparedAction(request: request, now: now)
        }
    }

    // MARK: - Research (P1-701)

    private static func composeResearch(
        request: OperatorRequest,
        activity: [ObservedActivity],
        now: Date
    ) -> ComposedOperatorArtifact {
        // Flattened and bounded, not merely trimmed: trimming strips the *ends* of a string, so an
        // interior newline reached the title and the `## Query` section below and could open a
        // heading of its own inside prose this composer owns. See
        // ``WatchTarget/sanitizedProseText(_:)``.
        let query = WatchTarget.sanitizedProseText(request.query)
        let title = "Research Brief: \(query?.isEmpty == false ? query! : "Recent Activity")"
        var lines: [String] = []
        lines.append("# \(title)")
        // No "No external network authority." claim here. The composer cannot know what the injected
        // `OperatorDataSource` did — and in the shipping app it is `LiveOnChainOperatorDataSource`,
        // which issues a live JSON-RPC call per watchlist entry for *whatever* operator asked,
        // without branching on kind. `RuntimeHost.runResearchBrief(query:watchlist:)` accepts a
        // watchlist, so a brief could make an outbound request naming the user's address to a
        // third-party provider while its own artifact asserted the opposite, in a record the user is
        // meant to be able to trust. A privacy claim belongs to the component that can honestly make
        // it; the one thing this composer knows is where it read from.
        // "Composed from the local receipt ledger" was the same overclaim one layer down: the
        // composer reads from whatever `OperatorDataSource` it was handed, and the shipping
        // conformer merges live JSON-RPC snapshots into that feed. State the one thing that is
        // true of every conformer.
        lines.append("Generated \(stamp(now)) · Composed from the operator data source.")
        lines.append("")
        lines.append("## Query")
        // Fourth site of the locality claim, three lines above the branch it was removed from.
        // Same reading: the composer summarizes whatever feed it was handed, not "local activity".
        //
        // Rendered as a line of its own, so flattening is not enough on its own: see
        // ``WatchTarget/lineSafeProseText(_:)``. The *title* above and the summary below interpolate
        // the query mid-string, where no block can open, so they keep the unescaped spelling.
        lines.append(
            WatchTarget.lineSafeProseText(request.query)
                ?? "_No query supplied — summarizing recent activity._"
        )
        lines.append("")
        lines.append(scopeSection(request))
        lines.append("## Findings (\(activity.count))")
        if activity.isEmpty {
            // Same reading as the summary below: "local" is a claim about where the feed came from,
            // and the composer does not know. It matters most on exactly this branch — an empty feed
            // is what a *storage fault* produces (`ReceiptBackedOperatorDataSource` logs and returns
            // `[]`), and that source's own comment says a brief stating "no recent activity" must
            // not be how a storage fault presents itself.
            lines.append("_No matching activity was returned for this scope._")
        } else {
            lines.append(contentsOf: activity.map { bullet($0) })
        }
        lines.append("")
        lines.append("## Summary")
        lines.append(researchSummary(query: query, activity: activity))
        return ComposedOperatorArtifact(
            title: title,
            body: lines.joined(separator: "\n"),
            findingCount: activity.count,
            alertCount: 0,
            preparedActions: [],
            // The brief renders every entry it is handed, so every entry is attributed.
            attributedSourceReceiptIDs: activity.compactMap(\.sourceReceiptID)
        )
    }

    private static func researchSummary(query: String?, activity: [ObservedActivity]) -> String {
        guard !activity.isEmpty else {
            // The locality claim was removed from the non-empty branch below and left here, in the
            // same function — and this is the branch a storage fault reaches. "The local ledger
            // holds no entries" over a ledger that is full, because `latest(limit:)` threw, is the
            // false reassurance the data source's comment warns about.
            return "No entries in scope were returned for this brief; nothing to report yet."
        }
        // Three states, not `!isSuccess`. `ObservedActivity.isSuccess` is documented as unsafe for
        // exactly this question: it answers false for `.unobserved` too, so a provider timeout was
        // reported as an entry that "did not" succeed — a durable, receipted claim that something
        // went wrong when the only thing that happened is that we could not look.
        let successes = activity.filter { $0.outcome == .succeeded }.count
        let failures = activity.filter { $0.outcome == .failed }.count
        let gaps = activity.filter { $0.outcome == .unobserved }.count
        let focus = query?.isEmpty == false ? " on “\(query!)”" : ""
        var summary = "Reviewed \(activity.count) entr\(activity.count == 1 ? "y" : "ies")\(focus): \(successes) succeeded"
        if failures > 0 { summary += ", \(failures) did not" }
        if gaps > 0 { summary += ", \(gaps) could not be observed" }
        // No locality claim. See the note in `composeResearch` — the composer cannot know what the
        // injected `OperatorDataSource` did, and in the shipping app it reaches the network. This
        // sentence used to assert "derived from on-device records only" thirty-five lines after the
        // comment explaining why that must not be said.
        summary += "."
        return summary
    }

    // MARK: - On-Chain Watch (P1-702)

    private static func composeWatch(
        request: OperatorRequest,
        activity: [ObservedActivity],
        now: Date
    ) -> ComposedOperatorArtifact {
        // One section per *distinct* account. `WatchTarget.id` is the `(chain, address)` pair this
        // whole feature keys on, and a watchlist can carry the same pair twice: `OperatorRequest`
        // rebuilds it by decoding JSON straight off a proposal's parameters and does not dedupe.
        // Iterating the raw list rendered that account twice, added its failures to `alertCount`
        // twice, and queued two identical prepared actions for the Approval Inbox — while
        // `findingCount` below asks `targets.contains`, so it counted the same events once. An
        // artifact reporting more alerts than findings, for one account listed under two spellings.
        let targets = distinctTargets(request.watchlist)
        // The events this report will actually attribute, named once and used for every claim derived
        // from them — the finding count below and the receipts the artifact links. `matches` keys on
        // `WatchTarget.chainKey`, the same key that made `targets` distinct, so an event can satisfy
        // at most one target and this cannot double-count. That used to be asserted here and be
        // false: the two sides normalized chains differently.
        let attributed = activity.filter { entry in targets.contains { matches(entry, $0) } }
        let title = "On-Chain Watch: \(watchScope(targets))"
        var lines: [String] = []
        lines.append("# \(title)")
        lines.append("Generated \(stamp(now)) · Read-only monitoring · No transaction was signed or broadcast.")
        lines.append("")

        var alertCount = 0
        var preparedActions: [PreparedAction] = []

        if targets.isEmpty {
            lines.append("_No accounts or contracts are on the watchlist._")
        } else {
            for target in targets {
                let matched = activity.filter { matches($0, target) }
                // Only `.failed` is an alert. `.unobserved` is a gap in *our* monitoring, reported
                // separately below rather than counted as something wrong with the account — a
                // provider timeout used to render as "⚠️ 1 alert" on a durable, receipted artifact
                // and put that count on the receipt.
                let failures = matched.filter { $0.outcome == .failed }
                let gaps = matched.filter { $0.outcome == .unobserved }
                alertCount += failures.count
                // The chain is flattened for the same reason the address is normalized: it is the
                // caller's string, it ends a line this composer owns, and `chain.inScope` admits a
                // leading or trailing break because `ChainScopeReference.resolve` trims before it
                // matches. See ``WatchTarget/flattenedChain(_:)``.
                lines.append("## \(target.displayName) — \(WatchTarget.flattenedChain(target.chain))")
                // The same spelling that crosses the boundary as `preparedActionAddress`, not the
                // raw one. `AddressFormatCheck` admits a bare 40-hex body and a whitespace-padded
                // one, so a watchlist entry can legitimately reach here spelled differently from
                // the value the prepared packet carries — and then the body a human opens to check
                // an approval and the packet they actually approve show two different strings for
                // one account. `enforcingPreparedTarget` exists because those two must be
                // comparable by eye; rendering the raw form here breaks the same invariant one
                // layer down, on the path that does not involve a provider at all.
                lines.append("`\(WatchTarget.normalizedAddress(target.address))`")
                if matched.isEmpty {
                    lines.append("_No recent observed activity._")
                } else {
                    // The observed count excludes `.unobserved`, because those are the entries we
                    // explicitly did *not* observe. Counting the whole matched set here produced
                    // "Observed 1 event · 1 monitoring gap." on a durable, receipted artifact — a
                    // sentence that contradicts itself within six words, and on a target whose only
                    // entry was a provider timeout it asserted an observation that never happened.
                    // The gap is still reported, in the clause right next to it; what changes is
                    // that it is no longer also counted as having been seen.
                    let observed = matched.count - gaps.count
                    lines.append("Observed \(observed) event\(observed == 1 ? "" : "s")\(failures.isEmpty ? "" : " · \(failures.count) alert\(failures.count == 1 ? "" : "s")")\(gaps.isEmpty ? "" : " · \(gaps.count) monitoring gap\(gaps.count == 1 ? "" : "s")").")
                    lines.append(contentsOf: matched.map { bullet($0) })
                    // Prepared *only* when something was actually found wrong with the account.
                    //
                    // This used to fire on `!matched.isEmpty` — on having observed anything at all.
                    // The shipping data source manufactures one successful balance snapshot per
                    // target on every run, so every watch run produced a prepared action, and
                    // `MissionControlHomeModel.runOperator` escalates on `preparedActionCount > 0`
                    // straight into `runPreparedAction` → a `draftTransaction` at `.highRisk`. The
                    // result was a wallet-draft approval in front of the user on every single run of
                    // a surface whose own artifact says "Read-only monitoring" and "_None —
                    // monitoring only._", with no finding behind it. Observe-mode blocks it and a
                    // human still has to approve, which is precisely why repeated contentless
                    // approval prompts are the harm: they are how an approval gate gets trained away.
                    //
                    // `.unobserved` is deliberately excluded. Escalating on a provider error would
                    // put a wallet draft in front of someone because the network was down.
                    if !failures.isEmpty {
                        preparedActions.append(
                            PreparedAction(
                                title: "Review recent activity for \(target.displayName)",
                                // Flattened, for the reason the address beside it is normalized:
                                // this value crosses the boundary into `preparedActionChain` on a
                                // receipt and an approval surface. See
                                // ``WatchTarget/flattenedChain(_:)``.
                                chain: WatchTarget.flattenedChain(target.chain),
                                // Normalized, not keyed: this value crosses the `ToolCallArtifact`
                                // boundary into `preparedActionAddress`, which the output schema
                                // validates as a 0x-prefixed 40-hex address *after* the artifact
                                // has been persisted. Case is preserved because the mixed case in
                                // a checksummed address is the EIP-55 integrity check, and this is
                                // the value a human reads on the approval surface.
                                address: WatchTarget.normalizedAddress(target.address),
                                rationale: "Observed \(failures.count) unsuccessful on-chain event\(failures.count == 1 ? "" : "s"); queue a confirm-first review before any action."
                            )
                        )
                    }
                }
                lines.append("")
            }
        }

        lines.append("## Prepared actions (escalate to Approval Inbox)")
        if preparedActions.isEmpty {
            lines.append("_None — monitoring only._")
        } else {
            for action in preparedActions {
                // The account is named in the bullet, not just the target's `displayName` inside
                // the title. `displayName` prefers the caller's `label`, which no deterministic
                // check validates, so on a multi-target watch the only thing distinguishing two
                // prepared actions from each other was a pair of caller-supplied nicknames. The
                // address and chain here are the same normalized/flattened spellings that cross
                // the `ToolCallArtifact` boundary, so this list and `preparedActionAddress` are
                // comparable by eye.
                lines.append("- **\(action.title)** — `\(action.address)` on \(action.chain) — \(action.rationale)")
            }
            lines.append("")
            lines.append("_Prepared actions are not executed autonomously. Each requires confirm-first approval._")
            // Which of several prepared targets the *record* is about.
            //
            // `preparedActionCount` crosses the boundary alongside a single
            // `preparedActionChain`/`preparedActionAddress` pair, taken from
            // `preparedActions.first`, because `artifactOutputSchema` is
            // `allowsAdditionalFields: false` and carries one pair. A watch over several accounts
            // can prepare several actions, so a human reading "2 prepared actions" on an approval
            // raised from this run is looking at a draft for exactly one of them, with nothing on
            // either surface saying which. Widening the schema would change the record shape and
            // its app-side consumer; what the artifact can do on its own is stop being ambiguous
            // about it. Said only when there is more than one, so the single-target case — every
            // prepared-action packet, and the common watch — gains no noise.
            if preparedActions.count > 1, let escalated = preparedActions.first {
                let others = preparedActions.count - 1
                lines.append("")
                lines.append(
                    "_This run escalates one of them: `\(escalated.address)` on \(escalated.chain). "
                        + "The other \(others) \(others == 1 ? "is" : "are") reported here only, and "
                        + "\(others == 1 ? "needs" : "need") a run of \(others == 1 ? "its" : "their") own to be prepared for approval._"
                )
            }
        }

        return ComposedOperatorArtifact(
            title: title,
            body: lines.joined(separator: "\n"),
            // The events this report actually attributed, not every event it was handed.
            //
            // Research and identity review render their whole feed (identity review partitions it
            // exactly into changes/anomalies/stale), so `activity.count` is the right denominator
            // there. The watch is the one kind that *drops* input: `matches` refuses another chain's
            // events and chain-unknown events, and `alertCount` above is already summed over matched
            // events only. Counting the raw feed here made the two disagree — a watch handed three
            // events of which one matched reported "3 findings, 0 alerts" while the body said
            // "Observed 1 event" and the two excluded failures appeared nowhere. With an empty
            // watchlist it was worse: the body renders no events at all and the count was still the
            // full feed.
            findingCount: attributed.count,
            alertCount: alertCount,
            preparedActions: preparedActions,
            // The same subset, for the same reason: the artifact's receipt links are a claim about
            // what the run was derived from, and linking a chain's events to a report that refused
            // to read them is that claim being false.
            attributedSourceReceiptIDs: attributed.compactMap(\.sourceReceiptID)
        )
    }

    // MARK: - Identity / Account Review (P1-703)

    private static func composeIdentityReview(
        request: OperatorRequest,
        activity: [ObservedActivity],
        now: Date
    ) -> ComposedOperatorArtifact {
        // Same treatment as `composeResearch`'s query, and for the same reason: the trim this
        // replaced left interior line breaks intact, and `identityID` has no deterministic check
        // behind it. See ``WatchTarget/sanitizedProseText(_:)``.
        let identity = WatchTarget.sanitizedProseText(request.identityID)
        let title = "Identity & Account Review: \(identity?.isEmpty == false ? identity! : "Active Identity")"
        // Partitioned on the three-state `outcome`, not on `!isSuccess`. `.unobserved` is a
        // statement about *us* — a provider timeout or an unreachable RPC — so folding it in with
        // `.failed` wrote "⚠️ 1 anomaly" onto a durable, receipted review of the user's identity
        // because the network was down. `alertCount` goes onto the receipt, which is what makes
        // this a correctness question rather than a wording one.
        let changes = activity.filter { $0.outcome == .succeeded }
        let unresolved = activity.filter { $0.outcome == .failed }
        let gaps = activity.filter { $0.outcome == .unobserved }
        let stale = unresolved.filter { now.timeIntervalSince($0.occurredAt) > staleAfter }
        let anomalies = unresolved.filter { now.timeIntervalSince($0.occurredAt) <= staleAfter }

        var lines: [String] = []
        lines.append("# \(title)")
        // No "No cross-identity data accessed." claim, for the reason set out in `composeResearch`:
        // the composer cannot know what the injected `OperatorDataSource` did. `runOperator` is
        // public and does not reject a watchlist on this kind, and
        // `LiveOnChainOperatorDataSource.recentActivity` branches on the *watchlist*, not on the
        // operator kind — so an identity review carrying a watchlist issues a live JSON-RPC read
        // naming another account, and that account's balance renders in the body. The claim was
        // false precisely when it mattered.
        lines.append("Generated \(stamp(now)) · Scoped to identity \(identity?.isEmpty == false ? "“\(identity!)”" : "(active)").")
        lines.append("")
        lines.append(section("Changes (\(changes.count))", items: changes, empty: "_No recent changes._"))
        lines.append(section("Anomalies (\(anomalies.count))", items: anomalies, empty: "_No anomalies detected._"))
        lines.append(section("Stale tasks (\(stale.count))", items: stale, empty: "_Nothing has gone stale._"))
        // Reported, because a gap is worth telling the user about — but as its own heading, so it
        // never reads as a finding against the account.
        lines.append(
            section("Monitoring gaps (\(gaps.count))", items: gaps, empty: "_Everything in scope was observed._")
        )
        lines.append("## Scope")
        // States the scope that was *requested*, which is the only thing the composer owns. The
        // replacement for "No cross-identity data accessed." asserted that the entries below were
        // attributed to this identity — and `composeIdentityReview` never reads
        // `activity[].identityID`; it renders whatever feed it was handed. That made it false in
        // exactly the scenario the comment above describes: a review carrying a watchlist reaches
        // `LiveOnChainOperatorDataSource`, which branches on the watchlist rather than the operator
        // kind, so another account's balance renders here — and `ReceiptBackedOperatorDataSource`
        // identity-filters only its own half, never the live entries appended after it. Claiming
        // attribution we did not perform is the same overclaim one sentence further on.
        lines.append("This review was requested scoped to \(identity?.isEmpty == false ? "identity “\(identity!)”" : "the active identity"); the entries below are what the operator data source returned for it.")

        return ComposedOperatorArtifact(
            title: title,
            body: lines.joined(separator: "\n"),
            findingCount: activity.count,
            // Gaps are deliberately not alerts. An alert is a claim that something is wrong with
            // the account; "we could not look" is not one, and there is no finding behind it.
            alertCount: anomalies.count + stale.count,
            preparedActions: [],
            // The review partitions its feed exactly into changes/anomalies/stale/gaps, so every
            // entry is rendered under one of the four headings and every entry is attributed.
            attributedSourceReceiptIDs: activity.compactMap(\.sourceReceiptID)
        )
    }

    // MARK: - Prepared action packet (P1-702, confirm-first)

    private static func composePreparedAction(request: OperatorRequest, now: Date) -> ComposedOperatorArtifact {
        let target = request.watchlist.first
        let name = target?.displayName ?? "action"
        let title = "Prepared Action Packet: \(name)"
        // The packet is the one artifact a human reads before approving a high-risk
        // `draftTransaction`, and `query` lands two lines above the `## Target` block that names the
        // account. Unflattened it could open a second `## Target` of its own, ahead of the
        // composer's — the defect found on `label`, on the surface where it matters most.
        let intent = WatchTarget.sanitizedProseText(request.query)
        var lines: [String] = []
        lines.append("# \(title)")
        lines.append("Generated \(stamp(now)) · Confirm-first · **Prepared only — nothing was signed or broadcast.**")
        lines.append("")
        lines.append("## Intended action")
        // The one site where a forged block is worth the most, so it gets the line-start treatment
        // rather than flattening alone: `"## Target"` needs no newline to open a heading of its own
        // two lines above the composer's. See ``WatchTarget/lineSafeProseText(_:)``.
        lines.append(
            WatchTarget.lineSafeProseText(request.query)
                ?? "Review the watched account and decide on a follow-up."
        )
        if let target {
            lines.append("")
            lines.append("## Target")
            // Flattened, like the rendered chain in `composeWatch` — see
            // ``WatchTarget/flattenedChain(_:)``. This block is the deterministic statement of which
            // account the packet is for, in the one artifact a human reads before approving a
            // high-risk `draftTransaction`; a chain carrying a trailing break ends the line here and
            // writes an unowned line into it.
            lines.append("- Chain: \(WatchTarget.flattenedChain(target.chain))")
            // Normalized, for the same reason as `composeWatch`'s rendered address: this block is
            // the deterministic statement of *which account* the packet is for, and it has to be
            // the same string as the `preparedActionAddress` the approval is drafted against.
            lines.append("- Address: `\(WatchTarget.normalizedAddress(target.address))`")
        }
        lines.append("")
        lines.append("## Governance")
        lines.append("This packet requires explicit human approval before any execution. It carries no authority to move funds on its own.")

        var prepared: [PreparedAction] = []
        if let target {
            prepared.append(
                PreparedAction(
                    title: "Confirm: \(name)",
                    // Flattened, for the same reason as `composeWatch`'s prepared action.
                    chain: WatchTarget.flattenedChain(target.chain),
                    // Normalized, for the same reason as `composeWatch`'s prepared action.
                    address: WatchTarget.normalizedAddress(target.address),
                    rationale: intent ?? "Operator-prepared, awaiting human confirmation."
                )
            )
        }

        return ComposedOperatorArtifact(
            title: title,
            body: lines.joined(separator: "\n"),
            findingCount: 0,
            alertCount: 0,
            preparedActions: prepared,
            // A packet describes intent only: the executor reads no ledger for this kind, so there is
            // no observed event to attribute and nothing honest to link.
            attributedSourceReceiptIDs: []
        )
    }

    // MARK: - Confirm-first guarantee

    /// The statement a body must make when the run prepared an action it did not take.
    ///
    /// The deterministic composers above already say this in their own words, so this is re-applied
    /// to exactly one thing: a body this package did not author. ``OperatorExecutor`` replaces the
    /// composed body *wholesale* with the provider's text on a remote route, and the prepared-action
    /// operator declares `usesInference: true` — so the artifact recording a high-risk, unexecuted
    /// wallet packet kept its `preparedActions` and `preparedActionCount` from the composer while its
    /// body, the part a human reads in Mission Control and in an export, became unvalidated provider
    /// prose with the confirm-first statement gone. The model is instructed not to claim a wallet
    /// action was executed; an instruction to a model is not a guarantee, and this is the one body
    /// whose subject is an action that must not have happened yet.
    static let confirmFirstStatement =
        "_Prepared only — nothing was signed or broadcast. Every prepared action requires explicit human approval before any execution._"

    /// `body` with ``confirmFirstStatement`` appended whenever the run carries prepared actions (or
    /// *is* a prepared-action packet).
    ///
    /// Additive on purpose: the provider's prose is kept, because what has to be restored is the
    /// claim about authority, not the description of the work. A body pushed past
    /// `ArtifactSchema.maximumContentLength` by the appended statement is refused by the executor's
    /// schema guard, which is the fail-closed direction.
    ///
    /// **Unconditional**, for the reason set out at length on
    /// ``enforcingPreparedTarget(_:preparedActions:)``. This used to skip a body that "already makes
    /// the statement", tested with `body.contains(confirmFirstStatement)` — the identical
    /// provider-controlled substring test that was removed from the sibling function and left here,
    /// guarding the *stronger* of the two claims.
    ///
    /// `String.contains` is a plain substring test over the whole body, and the only party that
    /// writes the body on this path is the untrusted one. A provider could assert execution in the
    /// prose a human reads and paste the exact statement somewhere Markdown does not render — an
    /// HTML comment, a fenced block, a reference-link title — and the deterministic restoration
    /// never appeared. The rendered artifact for a high-risk `draftTransaction` would then say the
    /// transaction was broadcast, with nothing anywhere on the surface contradicting it, while
    /// `preparedActionCount` on the receipt still said the action was only prepared. The one body
    /// whose subject is an action that must not have happened yet is the last place to let the
    /// author of that body decide whether the guarantee gets stated.
    ///
    /// The cost is the same one the sibling pays: a provider that legitimately emitted the exact
    /// statement gets it twice. A redundant line is not a defect; a missing guarantee is.
    ///
    /// **Leading, not trailing** — see ``markdownSafePrefixing(_:onto:)``. Making the append
    /// unconditional fixed *whether* the statement is added; it did nothing about whether the added
    /// statement renders, and the provider controls every line above it.
    static func enforcingConfirmFirst(
        _ body: String,
        kind: OperatorKind,
        preparedActions: [PreparedAction]
    ) -> String {
        guard kind == .preparedAction || !preparedActions.isEmpty else { return body }
        return markdownSafePrefixing(confirmFirstStatement, onto: body)
    }

    /// `block` placed ahead of `body` so that nothing in `body` can decide whether `block` renders.
    ///
    /// Both restorations below used to *append*, and that is unsound when the body is the untrusted
    /// party's. CommonMark block parsing is strictly forward: a block opened on line N consumes
    /// lines after N and can never reach a line before it. So a trailing restoration is only as
    /// visible as the provider's last open construct allows, and three of them swallow to the end of
    /// the document regardless of blank lines — an HTML block of types 1–5 (`<!--`, `<script>`,
    /// `<style>`, `<?`, `<![CDATA[`) that never meets its end condition, which CommonMark emits as
    /// *raw HTML*, and a fenced code block that is never closed.
    ///
    /// A body ending in a bare `<!--` therefore erased both restorations completely: the artifact
    /// for a high-risk `draftTransaction` rendered as the provider's prose alone — "the transaction
    /// was sent" — with the confirm-first guarantee and the deterministic `## Prepared target` block
    /// present in the stored string and invisible in every renderer of it, including the Markdown
    /// export. That is the same "paste it somewhere Markdown does not render" move the unconditional
    /// appends were introduced to defeat, reaching the restoration itself instead of the test that
    /// used to guard it. The round that closed the detection hole pinned the hiding place with a
    /// *closed* `<!-- … -->`, which is exactly the one spelling that cannot swallow anything.
    ///
    /// Leading is the whole fix, and it needs no scanner: there is no line above line 1, so no
    /// construct the provider opens can contain the block. The blank line between them is what keeps
    /// the seam one-directional in the other sense too — it stops a provider's first line from being
    /// read as a setext underline for, or a lazy continuation of, the composer's last line.
    private static func markdownSafePrefixing(_ block: String, onto body: String) -> String {
        body.isEmpty ? block : block + "\n\n" + body
    }

    /// `body` with the prepared target restated deterministically, for a body this package did not
    /// author.
    ///
    /// The sibling of ``enforcingConfirmFirst(_:kind:preparedActions:)``, closing the other half of
    /// the same hole. ``OperatorExecutor`` replaces the composed body *wholesale* with the
    /// provider's text on a remote route, and `composePreparedAction`'s deterministic `## Target`
    /// block — the only place the body names the account — goes with it. Confirm-first restores the
    /// claim about *authority*; this restores the claim about *subject*, and a body that correctly
    /// says nothing was broadcast while naming the wrong account is still an approval surface
    /// disagreeing with the record behind it.
    ///
    /// That disagreement is not cosmetic: the composer's `PreparedAction.address` crosses the
    /// `ToolCallArtifact` boundary as `preparedActionAddress`, and `MissionControlHomeModel`
    /// escalates `runPreparedAction` against *that* value — so the address a human reads in the
    /// artifact and the address they actually approve would come from two different authors, one of
    /// them the untrusted one.
    ///
    /// Additive, like the confirm-first statement, and **unconditional** whenever the run prepared
    /// anything. A body pushed past `ArtifactSchema.maximumContentLength` by the appended block is
    /// refused by the executor's schema guard, which is the fail-closed direction.
    ///
    /// This used to skip any address "the body already names", on the reasoning that a provider who
    /// got it right should not be second-guessed. That test handed the decision to the one party
    /// this function exists to defend against, and it was wrong in both directions:
    ///
    /// - **It suppressed the block for the price of one hidden mention.** `String.contains` is a
    ///   plain substring test over the whole body, so a provider could name an impostor in the prose
    ///   a human reads and bury the real address anywhere — a footnote, a code fence, an HTML
    ///   comment Markdown does not render at all — and the deterministic restatement never appeared.
    ///   That is exactly the "approval surface disagreeing with the record behind it" this function
    ///   was written to close, reinstated by its own optimization.
    /// - **It failed to recognize a correct body.** The test is case-sensitive while
    ///   ``WatchTarget/normalizedAddress(_:)`` deliberately preserves EIP-55 case, so a provider
    ///   naming the right account in the all-lowercase form most tooling emits was treated as not
    ///   naming it at all.
    ///
    /// So the heuristic bought nothing it could be trusted for. Always emitting costs a redundant
    /// two lines on a body that already got it right, and buys a block that is always present,
    /// always ours, and always in the same place — which is what makes it readable as the
    /// authoritative statement of subject rather than one more claim competing with the prose.
    ///
    /// **Leading, not trailing** — see ``markdownSafePrefixing(_:onto:)``. A block the provider can
    /// bury inside an unterminated HTML block is not "always present" in any sense a reader
    /// benefits from.
    static func enforcingPreparedTarget(_ body: String, preparedActions: [PreparedAction]) -> String {
        guard !preparedActions.isEmpty else { return body }
        var lines = ["## Prepared target"]
        lines.append(contentsOf: preparedActions.map { "- `\($0.address)` on \($0.chain)" })
        return markdownSafePrefixing(lines.joined(separator: "\n"), onto: body)
    }

    // MARK: - Telemetry

    /// Derives inference telemetry from the *actual* input/output rather than hardcoded literals.
    ///
    /// `didInvokeModel` is what the run *did*, not what its spec permits — the distinction this
    /// parameter exists to force. It was named `usesInference` and callers passed
    /// `OperatorSpec.usesInference` straight through, which is a declaration about the operator, not
    /// an observation about the run. An operator declaring `usesInference: true` composes its body
    /// deterministically whenever the resolved route is local, so every such run reported estimated
    /// prompt/completion tokens and `usesInference: true` for a model it never called — and
    /// `ReceiptContentPresenter` reads that flag to decide whether to render the privacy-impact row,
    /// so the receipt claimed an inference hop that did not happen. Three of four catalog operators
    /// declare `usesInference: true` and the shipping router is local-first, so this was the common
    /// path, not an edge case.
    ///
    /// A run that invoked no model reports zero tokens: the route is still recorded for provenance,
    /// but nothing presents it as AI inference. (P1-AI-103)
    public static func telemetry(
        route: ModelRoute,
        didInvokeModel: Bool,
        request: OperatorRequest,
        activity: [ObservedActivity],
        body: String,
        duration: Double
    ) -> InferenceTelemetry {
        guard didInvokeModel else {
            return InferenceTelemetry(
                route: route,
                promptTokens: 0,
                completionTokens: 0,
                durationSeconds: duration,
                estimatedCost: 0,
                tokensEstimated: false,
                usesInference: false
            )
        }
        let promptText = ([request.query ?? ""] + activity.map { "\($0.title) \($0.detail)" }).joined(separator: " ")
        let promptTokens = estimatedTokens(promptText)
        let completionTokens = estimatedTokens(body)
        return InferenceTelemetry(
            route: route,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            durationSeconds: duration,
            // Derived from the route's per-token rates, not a hardcoded literal: local routes bill $0
            // by rate, a remote route bills its declared price. (P1-AGENT-101 cost telemetry)
            estimatedCost: route.estimatedCost(promptTokens: promptTokens, completionTokens: completionTokens),
            // Counts are approximated from content length for on-device runs, so mark them estimated.
            tokensEstimated: true
        )
    }

    /// The token estimate for `text`, under the same ceiling a *reported* count is held to.
    ///
    /// ``maximumReportedTokens`` is documented as "the largest token count this package will carry",
    /// and the accumulation-safety argument on it rests on that being true of every count, not only
    /// of the ones a provider reported. It was applied on one side: ``reportedTokenCounts`` refuses
    /// an over-ceiling report and then falls back to *this*, which was unbounded — so the escape
    /// from a disbelieved count was a path with no bound on it at all. The input is not the
    /// provider's but it is not this package's either: the estimate is taken over
    /// `ModelInferenceRequest.prompt`, which embeds the whole `OperatorDataSource` feed, and the
    /// feed's `title`/`detail` are explicitly "not the caller's to bound" (see
    /// ``WatchTarget/flattenedText(_:)``). Clamping here makes the ceiling total rather than
    /// conditional, which is what lets the invariant be stated as a property of the recorded
    /// telemetry instead of a property of the fixtures the tests happen to use.
    ///
    /// Clamping rather than refusing, because unlike a reported count there is nothing dishonest to
    /// fall back *to*: the estimate is already the fallback, and a prompt large enough to reach ten
    /// million tokens has no meaningful number to report either way. The flag stays
    /// `tokensEstimated: true` at every site that reaches here, so the value is never presented as
    /// something that was measured.
    static func estimatedTokens(_ text: String) -> Int {
        min(EstimatedTokenCounter.count(text), maximumReportedTokens)
    }

    /// The largest token count this package will carry from a provider's own report.
    ///
    /// A ceiling is needed because `InferenceTelemetry.promptTokens`/`completionTokens` are plain
    /// `Int`s that flow, unexamined, into `AgentSession.note(telemetry:)` — which does
    /// `promptTokens += promptTokens` — and into `InferenceTelemetry.totalTokens`, which is
    /// `promptTokens + completionTokens`. Both are checked arithmetic, so a provider reporting
    /// `Int.max` *traps the process* on the first surface that adds the pair up. Ten million is far
    /// above any real context window and far below the point where accumulation can overflow.
    static let maximumReportedTokens = 10_000_000

    /// The token counts and estimate flag to record for a run that **did** call a model, given what
    /// the provider said about it.
    ///
    /// The executor's split is that the route and the clock are ours and the token counts are the
    /// provider's. That is right, and it was applied without ever asking whether what the provider
    /// reported *is a count*. `InferenceTelemetry`'s fields are non-optional, so the one thing a
    /// provider that does not report usage can put there is `0` — and `0` is also the honest answer
    /// for a run that consumed nothing. The two were indistinguishable and both were believed:
    ///
    /// - **Zero against a non-empty prompt.** A model that was handed this package's prompt — the
    ///   watchlist JSON, the activity feed and the deterministic draft — cannot have consumed zero
    ///   prompt tokens. Recording `0` claimed a hop that cost nothing on a route that bills, so the
    ///   artifact's `estimatedCost` row, the receipt's, and `AgentSession.estimatedCost` all said
    ///   the remote call was free. `EstimatedTokenCounter` exists for exactly this case and
    ///   documents the contract — "for providers that do not report token usage … always paired
    ///   with `tokensEstimated == true`" — so the fallback is an estimate that is *labelled* as
    ///   one, never a zero that is labelled as a measurement.
    /// - **Negative.** Not a count at all, and it does not merely render wrong: `estimatedCost`
    ///   is derived from the counts by rate, so a negative report *credits* the session ledger,
    ///   and the running `promptTokens`/`completionTokens` totals go backwards. A provider could
    ///   zero out the recorded cost of its own earlier calls.
    /// - **Absurdly large.** See ``maximumReportedTokens`` — the trapping case.
    ///
    /// Only the provider's numbers are second-guessed. The *fact* of the hop is the executor's
    /// observation and stays true either way, which is why this never returns `usesInference: false`.
    static func reportedTokenCounts(
        promptTokens: Int,
        completionTokens: Int,
        tokensEstimated: Bool,
        promptText: String,
        completionText: String
    ) -> (prompt: Int, completion: Int, estimated: Bool) {
        if isUsableCount(promptTokens, for: promptText), isUsableCount(completionTokens, for: completionText) {
            return (promptTokens, completionTokens, tokensEstimated)
        }
        return (estimatedTokens(promptText), estimatedTokens(completionText), true)
    }

    /// Whether `count` can be believed as the number of tokens `text` became.
    ///
    /// The two halves of the zero rule are symmetric and both of them are load-bearing. Zero is a
    /// measurement only when there was nothing to measure — that is the half that stops a paid
    /// remote hop being recorded as free. A *positive* count is a measurement only when there was
    /// something to measure, and that half was missing: `estimatedCost` is derived from the counts
    /// by the route's rates, so a provider that returned no content at all and reported
    /// ``maximumReportedTokens`` completion tokens billed the artifact's cost row, the receipt's,
    /// and `AgentSession.estimatedCost` for ten million tokens it never produced. That is the same
    /// "the provider authored its own cost" defect as the zero case, pointed the other way, and it
    /// is reachable on exactly the path the blank-response fallback already handles: an empty
    /// response body with whatever usage the provider cares to claim about it.
    ///
    /// Falling back costs nothing when the provider was honest, because the estimate of an empty
    /// string is zero — the same answer an honest report gives.
    private static func isUsableCount(_ count: Int, for text: String) -> Bool {
        guard count >= 0, count <= maximumReportedTokens else { return false }
        return (count > 0) == !text.isEmpty
    }

    /// Telemetry for a run that **did** call a model, assembled from what this package observed and
    /// what the provider reported — with the reported half checked by
    /// ``reportedTokenCounts(promptTokens:completionTokens:tokensEstimated:promptText:completionText:)``.
    ///
    /// The route, the clock and the fact of the hop are the executor's; the cost is always derived
    /// from the route's own rates rather than from anything the provider says it charges.
    public static func telemetry(
        route: ModelRoute,
        reported: InferenceTelemetry,
        promptText: String,
        completionText: String,
        duration: Double
    ) -> InferenceTelemetry {
        let counts = reportedTokenCounts(
            promptTokens: reported.promptTokens,
            completionTokens: reported.completionTokens,
            tokensEstimated: reported.tokensEstimated,
            promptText: promptText,
            completionText: completionText
        )
        return InferenceTelemetry(
            route: route,
            promptTokens: counts.prompt,
            completionTokens: counts.completion,
            durationSeconds: duration,
            estimatedCost: route.estimatedCost(
                promptTokens: counts.prompt,
                completionTokens: counts.completion
            ),
            tokensEstimated: counts.estimated,
            usesInference: true
        )
    }

    // MARK: - Rendering helpers

    private static func scopeSection(_ request: OperatorRequest) -> String {
        var scope = "## Scope\n"
        if request.watchlist.isEmpty {
            // The third site of the same overclaim, and the one that renders on *every* kind that
            // calls this helper. "Local activity ledger" names a source the composer cannot verify:
            // it is handed an `OperatorDataSource`, and the shipping conformer merges live JSON-RPC
            // snapshots into the feed. An empty watchlist narrows nothing — it does not mean the
            // run stayed on-device.
            scope += "Recent activity returned by the operator data source."
        } else {
            scope += "Watchlist: " + request.watchlist.map(\.displayName).joined(separator: ", ") + "."
        }
        // Sanitized here too. This helper renders on *every* kind that calls it, not just the
        // identity review, so an unflattened `identityID` reached the research brief and the watch
        // report as well — the widest of the four sites, and the one that made a kind which never
        // mentions an identity carry caller-authored structure.
        if let identity = WatchTarget.sanitizedProseText(request.identityID) {
            scope += " Identity: \(identity)."
        }
        return scope + "\n"
    }

    private static func section(_ heading: String, items: [ObservedActivity], empty: String) -> String {
        var lines = ["## \(heading)"]
        if items.isEmpty {
            lines.append(empty)
        } else {
            lines.append(contentsOf: items.map { bullet($0) })
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func bullet(_ activity: ObservedActivity) -> String {
        // `🔍` for a monitoring gap, so a reader can tell "we could not look" from "we looked and it
        // failed" at a glance. Collapsing both into `⚠️` is what let a provider timeout read as an
        // on-chain alert.
        let marker: String
        switch activity.outcome {
        case .succeeded: marker = "✅"
        case .failed: marker = "⚠️"
        case .unobserved: marker = "🔍"
        }
        // Flattened, like every other untrusted value this file renders. The composer owns the `- `
        // marker that starts this line, so nothing in the text can open a block *provided* the text
        // cannot end the line — and `title`/`detail` are the one pair that reached here unflattened.
        // They are not scope strings, so they are not bounded here; they are not the caller's to
        // shorten. See ``WatchTarget/flattenedText(_:)`` for why this is reachable rather than
        // theoretical.
        let title = WatchTarget.flattenedText(activity.title)
        let detail = WatchTarget.flattenedText(activity.detail)
        return "- \(marker) \(title) — \(detail) (\(stamp(activity.occurredAt)))"
    }

    /// The watchlist with repeated `(chain, address)` pairs collapsed, first spelling and original
    /// order kept, so the report names each account the way the caller first named it.
    private static func distinctTargets(_ targets: [WatchTarget]) -> [WatchTarget] {
        var seen: Set<String> = []
        return targets.filter { seen.insert($0.id).inserted }
    }

    private static func watchScope(_ targets: [WatchTarget]) -> String {
        guard !targets.isEmpty else { return "No accounts" }
        if targets.count == 1 { return targets[0].displayName }
        return "\(targets[0].displayName) +\(targets.count - 1) more"
    }

    /// Whether `activity` is on-chain activity for `target` — same address *and* same chain.
    ///
    /// The chain used to be ignored entirely, so one address watched on two chains collected the
    /// other chain's events: the observed-event counts, the alert counts derived from them, and the
    /// prepared-action rationales all cross-attributed between chains. An address is only unique
    /// within a chain, which is exactly why `WatchTarget.id` is keyed on the pair.
    ///
    /// An activity with no recorded chain is "chain unknown", not "any chain", so it does not match
    /// a chain-specific target. Attributing an unplaced event to a named chain would be inventing
    /// the one fact the record is missing.
    ///
    /// This is the posture `ReceiptBackedOperatorDataSource` already took when it narrowed the
    /// ledger to a watchlist — it keys on a `(chain, address)` pair and drops an entry with no
    /// chain. So the composer was the inconsistent half of one filter, not a second policy, and
    /// agreeing with it costs no activity that reached here from the shipping data source.
    private static func matches(_ activity: ObservedActivity, _ target: WatchTarget) -> Bool {
        // Both halves of the *same* key `WatchTarget.id` uses, which is what makes the claim above
        // — that an event can satisfy at most one target — actually true. It was not: the chain
        // side trimmed here and did not in `id`, so one event matched two "distinct" targets whose
        // chains differed only by whitespace, and both sides were lexical while `chain.inScope` is
        // canonical, so a watch scoped by a chain *alias* matched nothing at all. The address half
        // then kept that asymmetry after the chain half was fixed: `caseInsensitiveCompare` folds
        // case but compares lengths, so a padded address in the watchlist matched nothing while
        // still rendering as its own section. See ``WatchTarget/chainKey(_:)`` and
        // ``WatchTarget/addressKey(_:)``.
        guard let address = activity.address,
              WatchTarget.addressKey(address) == WatchTarget.addressKey(target.address) else {
            return false
        }
        guard let chain = activity.chain else { return false }
        return WatchTarget.chainKey(chain) == WatchTarget.chainKey(target.chain)
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
