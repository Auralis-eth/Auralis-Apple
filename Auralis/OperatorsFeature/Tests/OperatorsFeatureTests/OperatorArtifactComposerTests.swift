import AccountsCore
import Foundation
@testable import OperatorsFeature
import AuralisRuntime
import Testing

private let watched = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
private let reference = Date(timeIntervalSince1970: 1_700_000_000)

private func activity(
    _ title: String,
    chain: String? = nil,
    address: String? = nil,
    identityID: String? = nil,
    succeeded: Bool = true,
    at date: Date = reference
) -> ObservedActivity {
    ObservedActivity(
        title: title,
        detail: "detail for \(title)",
        occurredAt: date,
        chain: chain,
        address: address,
        identityID: identityID,
        isSuccess: succeeded
    )
}

@Suite("Operator telemetry honesty")
struct OperatorTelemetryTests {
    /// A run that called no model reports no tokens and no cost, *even on a route that bills*.
    ///
    /// The route is still carried for provenance, which is exactly why the counts have to be zero
    /// and `usesInference` false: downstream the route alone is indistinguishable from a real hop.
    /// Pinning this against a *paid remote* route is the point — it is the one combination where a
    /// nonzero `estimatedCost` would invent a charge for an inference that never happened, and it is
    /// reachable whenever a remote-routed operator declares `usesInference: false`.
    @Test
    func aRunThatInvokedNoModelClaimsNoTokensAndNoCost() {
        let paidRemote = ModelRoute(
            id: "test.remote.paid",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )

        let telemetry = OperatorArtifactComposer.telemetry(
            route: paidRemote,
            didInvokeModel: false,
            request: OperatorRequest(query: "a query long enough to estimate tokens from"),
            activity: [activity("Swap executed"), activity("Approval failed", succeeded: false)],
            body: String(repeating: "composed body ", count: 100),
            duration: 1.5
        )

        #expect(telemetry.usesInference == false)
        #expect(telemetry.promptTokens == 0)
        #expect(telemetry.completionTokens == 0)
        #expect(telemetry.totalTokens == 0)
        #expect(telemetry.estimatedCost == 0)
        // Not "estimated": zero is the exact count of tokens a model that never ran consumed.
        #expect(telemetry.tokensEstimated == false)
        // Duration and route survive — the run did take time, and where it *would* have run is a
        // recorded fact.
        #expect(telemetry.durationSeconds == 1.5)
        #expect(telemetry.route == paidRemote)
    }

    /// A run that did invoke a model estimates from the real input and output, prices the estimate
    /// through the route's own rates, and labels the counts as estimates.
    @Test
    func aRunThatInvokedAModelEstimatesFromRealContentAndPricesItFromTheRoute() {
        let paidRemote = ModelRoute(
            id: "test.remote.paid",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        let feed = [activity("Swap executed"), activity("Approval failed", succeeded: false)]
        let body = String(repeating: "composed body ", count: 100)

        let telemetry = OperatorArtifactComposer.telemetry(
            route: paidRemote,
            didInvokeModel: true,
            request: OperatorRequest(query: "a query long enough to estimate tokens from"),
            activity: feed,
            body: body,
            duration: 2
        )

        #expect(telemetry.usesInference)
        #expect(telemetry.tokensEstimated)
        #expect(telemetry.completionTokens == OperatorArtifactComposer.estimatedTokens(body))
        // The prompt estimate covers the query *and* the activity handed to the model, because both
        // were sent. Counting only the query would under-report what left the device.
        let promptText = (["a query long enough to estimate tokens from"]
            + feed.map { "\($0.title) \($0.detail)" }).joined(separator: " ")
        #expect(telemetry.promptTokens == OperatorArtifactComposer.estimatedTokens(promptText))
        #expect(telemetry.estimatedCost == paidRemote.estimatedCost(
            promptTokens: telemetry.promptTokens,
            completionTokens: telemetry.completionTokens
        ))
        #expect(telemetry.estimatedCost > 0)
    }

    /// A provider that reports no usage gets an estimate, never a zero recorded as a measurement.
    ///
    /// `InferenceTelemetry.promptTokens`/`completionTokens` are non-optional, so the only thing a
    /// provider that does not report usage can put in them is `0` — and the executor copied the pair
    /// straight through, cost included. A model that was handed this package's prompt (watchlist
    /// JSON, activity feed, deterministic draft) cannot have consumed zero prompt tokens, so on a
    /// *paid* route that recorded a remote hop as free: `estimatedCost` is derived from the counts by
    /// rate, and it reaches the artifact's provenance row, the receipt, and `AgentSession`'s running
    /// cost. `EstimatedTokenCounter` exists for exactly this case and documents the contract — an
    /// estimate always paired with `tokensEstimated == true`.
    @Test
    func aProviderReportingNoUsageIsEstimatedRatherThanRecordedAsZero() {
        let paidRemote = ModelRoute(
            id: "test.remote.paid",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        let prompt = "Query: gas usage\nActivity:\n- Swap executed: USDC→ETH"
        let completion = "A brief about recent transfers."

        let telemetry = OperatorArtifactComposer.telemetry(
            route: paidRemote,
            reported: InferenceTelemetry(
                route: paidRemote,
                promptTokens: 0,
                completionTokens: 0,
                durationSeconds: 0.25,
                estimatedCost: 0,
                tokensEstimated: false,
                usesInference: true
            ),
            promptText: prompt,
            completionText: completion,
            duration: 0.5
        )

        #expect(telemetry.promptTokens == OperatorArtifactComposer.estimatedTokens(prompt))
        #expect(telemetry.completionTokens == OperatorArtifactComposer.estimatedTokens(completion))
        // Labelled as the estimate it is, rather than presented as a count the provider measured.
        #expect(telemetry.tokensEstimated)
        #expect(telemetry.estimatedCost > 0)
        // The hop itself is the executor's observation and is unaffected.
        #expect(telemetry.usesInference)
        #expect(telemetry.durationSeconds == 0.5)
    }

    /// A count that cannot be a count is replaced by an estimate rather than carried.
    ///
    /// A negative report is not merely wrong: `estimatedCost` is derived from the counts, so it
    /// *credits* the session's cost ledger, and `AgentSession.note(telemetry:)` adds the counts into
    /// running totals that then go backwards — a provider zeroing out the recorded cost of its own
    /// earlier calls. `Int.max` is the other end: `InferenceTelemetry.totalTokens` is
    /// `promptTokens + completionTokens` and the session accumulates with `+=`, both of which are
    /// checked arithmetic, so a single such report traps the process on the first surface that adds
    /// the pair up.
    @Test(arguments: [
        (-1, 5),
        (5, -1),
        (Int.max, 1),
        (1, Int.max),
        (OperatorArtifactComposer.maximumReportedTokens + 1, 1)
    ])
    func anUnbelievableReportedCountIsReplacedByAnEstimate(prompt: Int, completion: Int) {
        let paidRemote = ModelRoute(
            id: "test.remote.paid",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )

        let telemetry = OperatorArtifactComposer.telemetry(
            route: paidRemote,
            reported: InferenceTelemetry(
                route: paidRemote,
                promptTokens: prompt,
                completionTokens: completion,
                durationSeconds: 0.25,
                // A cost the provider invented for itself, which is never the one recorded.
                estimatedCost: -1_000,
                tokensEstimated: false,
                usesInference: true
            ),
            promptText: "a prompt that did leave the device",
            completionText: "a response that came back",
            duration: 0.5
        )

        #expect(telemetry.promptTokens >= 0)
        #expect(telemetry.completionTokens >= 0)
        #expect(telemetry.promptTokens <= OperatorArtifactComposer.maximumReportedTokens)
        #expect(telemetry.completionTokens <= OperatorArtifactComposer.maximumReportedTokens)
        // Summing the pair is what traps, so the pinned property is that it is now safe to.
        #expect(telemetry.totalTokens == telemetry.promptTokens + telemetry.completionTokens)
        #expect(telemetry.tokensEstimated)
        // Cost is always derived from the route's rates, never from what the provider says it cost.
        #expect(telemetry.estimatedCost > 0)
    }

    /// A believable report is carried as reported, so the check above is about disbelief rather than
    /// about distrusting every provider number.
    @Test
    func believableReportedCountsAreKeptWithTheProvidersOwnEstimateFlag() {
        let paidRemote = ModelRoute(
            id: "test.remote.paid",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )

        let telemetry = OperatorArtifactComposer.telemetry(
            route: paidRemote,
            reported: InferenceTelemetry(
                route: paidRemote,
                promptTokens: 1_234,
                completionTokens: 567,
                durationSeconds: 0.25,
                estimatedCost: 42,
                tokensEstimated: false,
                usesInference: true
            ),
            promptText: "a prompt that did leave the device",
            completionText: "a response that came back",
            duration: 0.5
        )

        #expect(telemetry.promptTokens == 1_234)
        #expect(telemetry.completionTokens == 567)
        #expect(telemetry.tokensEstimated == false)
        #expect(telemetry.estimatedCost == paidRemote.estimatedCost(promptTokens: 1_234, completionTokens: 567))

        // And zero *is* a measurement when there was nothing to measure: a provider that returned no
        // content reporting no completion tokens is reporting the truth.
        let empty = OperatorArtifactComposer.telemetry(
            route: paidRemote,
            reported: InferenceTelemetry(
                route: paidRemote,
                promptTokens: 1_234,
                completionTokens: 0,
                durationSeconds: 0.25,
                estimatedCost: 0,
                tokensEstimated: false,
                usesInference: true
            ),
            promptText: "a prompt that did leave the device",
            completionText: "",
            duration: 0.5
        )
        #expect(empty.completionTokens == 0)
        #expect(empty.promptTokens == 1_234)
        #expect(empty.tokensEstimated == false)
    }

    /// …and the mirror of that rule: a positive count is a measurement only when there was something
    /// to measure.
    ///
    /// Only the zero half was checked, so the disbelief ran in one direction. `estimatedCost` is
    /// derived from the counts by the route's rates, so a provider that returned *no content at
    /// all* and reported ``OperatorArtifactComposer/maximumReportedTokens`` completion tokens was
    /// believed — and the artifact's cost row, the receipt's, and the running
    /// `AgentSession.estimatedCost` were billed $150 on this route for ten million tokens that do
    /// not exist. That is the same "the provider authored its own cost" defect as recording a paid
    /// hop as free, pointed the other way, and it lands on exactly the path the blank-response
    /// fallback already has to handle: an empty body with whatever usage the provider claims for
    /// it.
    ///
    /// Falling back costs an honest provider nothing, because the estimate of an empty string is
    /// zero — the same answer an honest report gives.
    @Test(arguments: [1, 5_000, OperatorArtifactComposer.maximumReportedTokens])
    func aPositiveCountAgainstTextThatDoesNotExistIsNotBelieved(reported: Int) {
        let paidRemote = ModelRoute(
            id: "test.remote.paid",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        let prompt = "Query: gas usage\nActivity:\n- Swap executed: USDC→ETH"

        let telemetry = OperatorArtifactComposer.telemetry(
            route: paidRemote,
            reported: InferenceTelemetry(
                route: paidRemote,
                promptTokens: 1_000,
                completionTokens: reported,
                durationSeconds: 0.25,
                estimatedCost: 0,
                tokensEstimated: false,
                usesInference: true
            ),
            promptText: prompt,
            // Nothing came back, so there is nothing a completion count could be counting.
            completionText: "",
            duration: 0.5
        )

        #expect(telemetry.completionTokens == 0)
        // The pair falls back together, so the two halves can never be one measurement and one
        // estimate presented as a single coherent total.
        #expect(telemetry.promptTokens == OperatorArtifactComposer.estimatedTokens(prompt))
        #expect(telemetry.tokensEstimated)
        // Billed for the prompt that really did leave the device, and for nothing else.
        #expect(
            telemetry.estimatedCost
                == paidRemote.estimatedCost(
                    promptTokens: OperatorArtifactComposer.estimatedTokens(prompt),
                    completionTokens: 0
                )
        )
    }

    /// The ceiling holds on the *estimate* too, which is where a disbelieved count lands.
    ///
    /// ``OperatorArtifactComposer/maximumReportedTokens`` is documented as the largest count this
    /// package will carry, and the argument that `AgentSession.note(telemetry:)`'s `+=` cannot trap
    /// rests on that. It was enforced on one side only: `reportedTokenCounts` refuses an
    /// over-ceiling *report* and then falls back to an estimate that had no bound at all, so the
    /// escape from a disbelieved number was the unbounded path. The text estimated over is not the
    /// provider's but it is not bounded by this package either — it is
    /// `ModelInferenceRequest.prompt`, which embeds the whole `OperatorDataSource` feed, whose
    /// `title`/`detail` are explicitly not the composer's to shorten.
    ///
    /// The sibling assertions in `anUnbelievableReportedCountIsReplacedByAnEstimate` state the
    /// ceiling as a property of the recorded telemetry, and they held there only because that test's
    /// fixture text is short. This pins it as a property of the function.
    @Test
    func theTokenCeilingBoundsTheEstimateAndNotOnlyTheReport() {
        // `EstimatedTokenCounter` is `(count + 3) / 4`, so this is one token past the ceiling.
        let enormous = String(repeating: "x", count: 4 * OperatorArtifactComposer.maximumReportedTokens + 1)
        #expect(OperatorArtifactComposer.estimatedTokens(enormous) == OperatorArtifactComposer.maximumReportedTokens)

        let paidRemote = ModelRoute(
            id: "test.remote.paid",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        // A provider report that is refused, falling back onto that same enormous text.
        let telemetry = OperatorArtifactComposer.telemetry(
            route: paidRemote,
            reported: InferenceTelemetry(
                route: paidRemote,
                promptTokens: -1,
                completionTokens: -1,
                durationSeconds: 0.25,
                estimatedCost: 0,
                tokensEstimated: false,
                usesInference: true
            ),
            promptText: enormous,
            completionText: enormous,
            duration: 0.5
        )

        #expect(telemetry.promptTokens <= OperatorArtifactComposer.maximumReportedTokens)
        #expect(telemetry.completionTokens <= OperatorArtifactComposer.maximumReportedTokens)
        #expect(telemetry.totalTokens == telemetry.promptTokens + telemetry.completionTokens)
        #expect(telemetry.tokensEstimated)
    }

    /// The same invoked run on a local route bills nothing — the cost comes from the route's rates,
    /// not from a literal, so an on-device hop is free *by rate* while still counting its tokens.
    @Test
    func aLocalModelHopCountsTokensButCostsNothing() {
        let telemetry = OperatorArtifactComposer.telemetry(
            route: DefaultModelRoutes.localLanguageModel,
            didInvokeModel: true,
            request: OperatorRequest(query: "on-device query"),
            activity: [],
            body: "a composed body",
            duration: 0.25
        )
        #expect(telemetry.usesInference)
        #expect(telemetry.promptTokens > 0)
        #expect(telemetry.completionTokens > 0)
        #expect(telemetry.estimatedCost == 0)
    }
}

@Suite("Composed watch reports")
struct ComposedWatchReportTests {
    /// The finding count must be the events the report actually attributed, not every event handed
    /// to the composer.
    ///
    /// `matches` deliberately drops another chain's events and chain-unknown events, and the alert
    /// count is summed over matched events only — so counting the raw feed made the two disagree on
    /// the same artifact. Here the composer is handed three events of which one matches: the body
    /// says "Observed 1 event", `alertCount` is 0 because the matched event succeeded, and a
    /// `findingCount` of 3 would be the artifact reporting two findings it refused to show and
    /// declined to count as alerts.
    @Test
    func findingCountCountsOnlyTheEventsTheReportAttributed() {
        let composed = OperatorArtifactComposer.compose(
            kind: .onChainWatch,
            request: OperatorRequest(watchlist: [WatchTarget(chain: "base", address: watched, label: "Treasury")]),
            activity: [
                activity("Mainnet transfer", chain: "ethereum", address: watched, succeeded: false),
                activity("Unplaced event", address: watched, succeeded: false),
                activity("Base transfer", chain: "Base", address: watched)
            ],
            now: reference
        )

        #expect(composed.findingCount == 1)
        #expect(composed.alertCount == 0)
        #expect(composed.body.contains("Observed 1 event"))
        #expect(composed.body.contains("Mainnet transfer") == false)
    }

    /// With nothing on the watchlist the body renders no events at all, so it cannot report
    /// findings — the previous count was the whole feed against a report with no sections in it.
    @Test
    func anEmptyWatchlistReportsNoFindingsEvenWithActivityOnHand() {
        let composed = OperatorArtifactComposer.compose(
            kind: .onChainWatch,
            request: OperatorRequest(),
            activity: [
                activity("Mainnet transfer", chain: "ethereum", address: watched),
                activity("Base transfer", chain: "base", address: watched, succeeded: false)
            ],
            now: reference
        )

        #expect(composed.findingCount == 0)
        #expect(composed.alertCount == 0)
        #expect(composed.preparedActions.isEmpty)
        #expect(composed.body.contains("No accounts or contracts are on the watchlist"))
    }

    /// Alerts are the matched *failures*, counted per target across a multi-target watch, and the
    /// findings are the union of what every target attributed.
    @Test
    func multiTargetWatchesCountFindingsAndAlertsPerTarget() {
        let other = "0x0000000000000000000000000000000000000001"
        let composed = OperatorArtifactComposer.compose(
            kind: .onChainWatch,
            request: OperatorRequest(watchlist: [
                WatchTarget(chain: "ethereum", address: watched, label: "Treasury"),
                WatchTarget(chain: "base", address: other, label: "Ops")
            ]),
            activity: [
                activity("Treasury transfer", chain: "ethereum", address: watched),
                activity("Treasury revert", chain: "ethereum", address: watched, succeeded: false),
                activity("Ops transfer", chain: "base", address: other, succeeded: false),
                activity("Unwatched account", chain: "ethereum", address: other)
            ],
            now: reference
        )

        #expect(composed.findingCount == 3)
        #expect(composed.alertCount == 2)
        // One prepared action per target that observed a `.failed` event, never per event — and
        // never merely per target that observed *something*, which is the rule this comment used to
        // state and which put a high-risk approval in front of the user on every quiet run. Both
        // targets in this fixture carry a real failure, which is why two is correct here; see
        // `successfulActivityAlonePreparesNoAction` and
        // `unobservedActivityIsNeitherAnAlertNorAPreparedAction` for the negative cases.
        #expect(composed.preparedActions.count == 2)
        #expect(composed.body.contains("Unwatched account") == false)
    }

    /// The same account listed twice is one account. `OperatorRequest(parameters:)` rebuilds the
    /// watchlist by decoding JSON off a proposal and does not dedupe, so a replayed or hand-built
    /// proposal can carry the pair twice — and iterating it twice rendered the account twice, summed
    /// its failures into `alertCount` twice, and queued two identical prepared actions, while
    /// `findingCount` counted its events once. More alerts than findings, for one account.
    @Test
    func aRepeatedWatchTargetIsRenderedCountedAndPreparedOnce() {
        let composed = OperatorArtifactComposer.compose(
            kind: .onChainWatch,
            request: OperatorRequest(watchlist: [
                WatchTarget(chain: "ethereum", address: watched, label: "Treasury"),
                WatchTarget(chain: "Ethereum", address: watched.lowercased(), label: "Treasury again")
            ]),
            activity: [activity("Treasury revert", chain: "ethereum", address: watched, succeeded: false)],
            now: reference
        )

        #expect(composed.findingCount == 1)
        #expect(composed.alertCount == 1)
        #expect(composed.preparedActions.count == 1)
        // The first spelling names the account, and the title does not claim a second one.
        #expect(composed.title == "On-Chain Watch: Treasury")
        #expect(composed.body.contains("Treasury again") == false)
    }

    /// A chain `chain.inScope` admits cannot end a line the composer owns.
    ///
    /// The address half of a target is normalized at every render and boundary site; the chain half
    /// was interpolated raw — at the end of `## <name> — <chain>`, of `- Chain: <chain>`, and into
    /// `PreparedAction.chain`, which crosses into the receipt as `preparedActionChain`. That is
    /// reachable *through* the check rather than around it: `ChainScopeReference.resolve` trims
    /// `.whitespacesAndNewlines` before matching, so `"ethereum\n"` resolves to Ethereum mainnet and
    /// passes `chain.inScope` — then splits the composer's heading and writes a line it never wrote
    /// into a durable, receipted artifact.
    ///
    /// Fails against the raw interpolation, where the heading line is `## Treasury — ethereum` only
    /// after a line break that is not there in the rendered body.
    @Test(arguments: ["ethereum\n", "\u{2028}ethereum", "  ethereum  ", "\tethereum\u{000B}"])
    func aChainTheScopeCheckAdmitsCannotBreakTheComposersLine(chain: String) throws {
        // The premise: every spelling here is one the governed path lets through.
        #expect(ChainScopeReference.resolve(chain) == ChainScopeReference.resolve("ethereum"))

        let composed = OperatorArtifactComposer.compose(
            kind: .onChainWatch,
            request: OperatorRequest(watchlist: [WatchTarget(chain: chain, address: watched, label: "Treasury")]),
            activity: [activity("Treasury revert", chain: "ethereum", address: watched, succeeded: false)],
            now: reference
        )

        let lines = composed.body.components(separatedBy: "\n")
        #expect(lines.contains("## Treasury — ethereum"))
        // The value that crosses the `ToolCallArtifact` boundary onto an approval surface is the
        // flattened one, so a receipt field cannot carry a line break either.
        let action = try #require(composed.preparedActions.first)
        #expect(action.chain == "ethereum")

        // The same property on the packet, where the chain sits inside the deterministic block that
        // names the account a human is about to approve a `draftTransaction` for.
        let packet = OperatorArtifactComposer.compose(
            kind: .preparedAction,
            request: OperatorRequest(watchlist: [WatchTarget(chain: chain, address: watched, label: "Treasury")]),
            activity: [],
            now: reference
        )
        #expect(packet.body.components(separatedBy: "\n").contains("- Chain: ethereum"))
        #expect(packet.preparedActions.first?.chain == "ethereum")
    }

    /// A watch that prepares several actions says which one the record is about.
    ///
    /// Only `preparedActions.first` crosses the `ToolCallArtifact` boundary: `artifactOutputSchema`
    /// is `allowsAdditionalFields: false` and declares one `preparedActionChain`/
    /// `preparedActionAddress` pair, while `preparedActionCount` reports all of them. So a human
    /// looking at an approval raised from a two-target watch sees "2 prepared actions" beside a
    /// draft for exactly one account, and the body — the evidence they would open to check — named
    /// neither address at all: the bullets carried only `displayName`, which prefers the caller's
    /// unvalidated `label`, so two prepared actions could even read under the same nickname.
    ///
    /// Widening the schema is a record-shape change with an app-side consumer; what the artifact can
    /// do on its own is name each prepared account in the spelling the boundary carries, and state
    /// which single one this run escalates.
    @Test
    func aMultiTargetWatchNamesEveryPreparedAccountAndWhichOneItEscalates() throws {
        let other = "0x0000000000000000000000000000000000000001"
        let composed = OperatorArtifactComposer.compose(
            kind: .onChainWatch,
            request: OperatorRequest(watchlist: [
                // Deliberately the same nickname on both, which is what `label` being unchecked
                // permits: the account has to be identifiable from something the caller does not own.
                WatchTarget(chain: "ethereum", address: watched, label: "Treasury"),
                WatchTarget(chain: "base", address: other, label: "Treasury")
            ]),
            activity: [
                activity("Treasury revert", chain: "ethereum", address: watched, succeeded: false),
                activity("Ops revert", chain: "base", address: other, succeeded: false)
            ],
            now: reference
        )

        #expect(composed.preparedActions.count == 2)
        let escalated = try #require(composed.preparedActions.first)
        // Every prepared account is named in the body, in the same spelling `preparedActionAddress`
        // carries, so the list and the record are comparable by eye.
        for action in composed.preparedActions {
            #expect(composed.body.contains("`\(action.address)` on \(action.chain)"))
        }
        // And the one the run actually escalates is identified as such.
        #expect(composed.body.contains("This run escalates one of them: `\(escalated.address)` on \(escalated.chain)."))
        #expect(composed.body.contains("The other 1 is reported here only"))
    }

    /// The single-target case gains no noise: there is nothing ambiguous about one prepared action,
    /// so the disambiguating sentence must not appear.
    @Test
    func aSingleTargetWatchDoesNotClaimItLeftAnythingUnescalated() {
        let composed = OperatorArtifactComposer.compose(
            kind: .onChainWatch,
            request: OperatorRequest(watchlist: [
                WatchTarget(chain: "ethereum", address: watched, label: "Treasury")
            ]),
            activity: [activity("Treasury revert", chain: "ethereum", address: watched, succeeded: false)],
            now: reference
        )

        #expect(composed.preparedActions.count == 1)
        #expect(composed.body.contains("`\(watched)` on ethereum"))
        #expect(composed.body.contains("This run escalates one of them") == false)
        #expect(composed.body.contains("reported here only") == false)
    }

    /// A watch never reports a prepared action for a target it observed nothing for, and every
    /// prepared action stays scoped to its own target's chain and address.
    @Test
    func preparedActionsStayScopedToTheirTargetAndAreNeverExecuted() throws {
        let quiet = "0x0000000000000000000000000000000000000002"
        let composed = OperatorArtifactComposer.compose(
            kind: .onChainWatch,
            request: OperatorRequest(watchlist: [
                WatchTarget(chain: "ethereum", address: watched, label: "Treasury"),
                WatchTarget(chain: "base", address: quiet, label: "Quiet")
            ]),
            activity: [activity("Treasury revert", chain: "ethereum", address: watched, succeeded: false)],
            now: reference
        )

        #expect(composed.preparedActions.count == 1)
        let action = try #require(composed.preparedActions.first)
        #expect(action.chain == "ethereum")
        #expect(action.address == watched)
        #expect(composed.body.contains("Prepared actions are not executed autonomously"))
        #expect(composed.body.contains("No transaction was signed or broadcast"))
    }

    /// The Blocker this suite previously pinned shut as correct.
    ///
    /// Preparing an action used to require only that *something* was observed, and the shipping data
    /// source manufactures one successful balance snapshot per target on every run. So every watch
    /// run produced a prepared action, and `MissionControlHomeModel` escalates on
    /// `preparedActionCount > 0` straight into a `draftTransaction` at `.highRisk` — a wallet-draft
    /// approval in front of the user on every run, with nothing behind it, from a surface whose own
    /// artifact says "Read-only monitoring".
    ///
    /// Three of this file's tests fed a *successful* event and asserted a prepared action came back,
    /// which is why the behaviour read as intended.
    @Test("a watch that observed only successful activity prepares nothing")
    func successfulActivityAlonePreparesNoAction() {
        let composed = OperatorArtifactComposer.compose(
            kind: .onChainWatch,
            request: OperatorRequest(watchlist: [
                WatchTarget(chain: "ethereum", address: watched, label: "Treasury")
            ]),
            activity: [activity("Treasury transfer", chain: "ethereum", address: watched)],
            now: reference
        )

        #expect(composed.preparedActions.isEmpty)
        #expect(composed.alertCount == 0)
        // Still a real report — the activity is observed and rendered, it just is not a finding.
        #expect(composed.findingCount == 1)
        #expect(composed.body.contains("_None — monitoring only._"))
    }

    /// `.unobserved` is a statement about us, not about the account.
    ///
    /// A watch data source reports its own provider and network failures through `ObservedActivity`.
    /// With one boolean those were indistinguishable from an on-chain failure, so an RPC timeout was
    /// written into a durable, receipted artifact as an alert against the user's address — and once
    /// the prepared-action trigger became "something failed", a network blip would have been the
    /// thing that queued a wallet draft for approval.
    @Test("a monitoring gap is neither an alert nor a reason to prepare an action")
    func unobservedActivityIsNeitherAnAlertNorAPreparedAction() {
        let composed = OperatorArtifactComposer.compose(
            kind: .onChainWatch,
            request: OperatorRequest(watchlist: [
                WatchTarget(chain: "ethereum", address: watched, label: "Treasury")
            ]),
            activity: [
                ObservedActivity(
                    title: "Live chain snapshot failed",
                    detail: "The read-only provider could not refresh this target.",
                    occurredAt: reference,
                    chain: "ethereum",
                    address: watched,
                    outcome: .unobserved
                )
            ],
            now: reference
        )

        #expect(composed.alertCount == 0)
        #expect(composed.preparedActions.isEmpty)
        // Reported, not hidden: a gap in monitoring is something the reader needs to know about.
        #expect(composed.body.contains("monitoring gap"))
        // ...and not *also* counted as observed. The gap clause was added beside a count that still
        // included the unobserved entry, so this exact fixture — a target whose only entry is a
        // provider timeout — rendered "Observed 1 event · 1 monitoring gap." into a durable,
        // receipted artifact: a sentence that contradicts itself within six words and asserts an
        // observation that never happened.
        #expect(composed.body.contains("Observed 0 events · 1 monitoring gap."))
        #expect(composed.body.contains("Observed 1 event") == false)
        // `findingCount` is the **attributed** count, not the observed one, and this fixture is where
        // the two differ: zero observed, one attributed. Pinned so the disagreement reads as the
        // decided invariant rather than as the bug it looks like beside the line above — the gap was
        // attributed to a watched target, which is exactly why the body names it. Nothing in
        // production reads the field, so narrowing it would only make artifacts already on disk mean
        // something else; see `ComposedOperatorArtifact.findingCount`.
        #expect(composed.findingCount == 1)
    }

    /// The observed count is the observed *subset*, with alerts and gaps both named beside it.
    ///
    /// Pinned on a mixed feed because the single-outcome fixtures cannot tell "excludes gaps" from
    /// "counts everything": here the three numbers are distinct, so an implementation that counted
    /// the whole matched set would have to report 3.
    @Test("the observed count excludes monitoring gaps on a mixed feed")
    func observedCountExcludesGapsWhenAllThreeOutcomesAreMatched() {
        let composed = OperatorArtifactComposer.compose(
            kind: .onChainWatch,
            request: OperatorRequest(watchlist: [
                WatchTarget(chain: "ethereum", address: watched, label: "Treasury")
            ]),
            activity: [
                activity("Treasury transfer", chain: "ethereum", address: watched),
                activity("Approval reverted", chain: "ethereum", address: watched, succeeded: false),
                ObservedActivity(
                    title: "Live chain snapshot failed",
                    detail: "provider timed out",
                    occurredAt: reference,
                    chain: "ethereum",
                    address: watched,
                    outcome: .unobserved
                )
            ],
            now: reference
        )

        #expect(composed.body.contains("Observed 2 events · 1 alert · 1 monitoring gap."))
        // The governance-bearing counts are unchanged by the wording: the gap is not an alert, and
        // every matched entry is still rendered and still attributed.
        #expect(composed.alertCount == 1)
        #expect(composed.findingCount == 3)
    }
}

@Suite("Composed read reports")
struct ComposedReadReportTests {
    /// Research renders its whole feed, so its finding count *is* the feed — the narrowing applied
    /// to the watch must not leak into the kinds that attribute everything they are given. The
    /// data source has already scoped this feed to the query.
    @Test
    func researchCountsEveryEntryItRenders() {
        let feed = [
            activity("Swap executed"),
            activity("Approval failed", succeeded: false),
            activity("Transfer", chain: "ethereum", address: watched)
        ]
        let composed = OperatorArtifactComposer.compose(
            kind: .research,
            request: OperatorRequest(query: "gas usage"),
            activity: feed,
            now: reference
        )

        #expect(composed.findingCount == feed.count)
        #expect(composed.alertCount == 0)
        #expect(composed.body.contains("Findings (3)"))
        for entry in feed {
            #expect(composed.body.contains(entry.title))
        }
        #expect(composed.title == "Research Brief: gas usage")
    }

    /// With no query the brief still names its real scope rather than claiming one it was not
    /// given, and it says so in the body instead of composing an empty heading.
    @Test
    func researchWithNoQuerySummarizesRecentActivityInsteadOfClaimingAQuery() {
        let composed = OperatorArtifactComposer.compose(
            kind: .research,
            request: OperatorRequest(watchlist: [WatchTarget(chain: "base", address: watched, label: "Treasury")]),
            activity: [],
            now: reference
        )

        #expect(composed.title == "Research Brief: Recent Activity")
        #expect(composed.body.contains("No query supplied"))
        #expect(composed.body.contains("Watchlist: Treasury"))
        #expect(composed.findingCount == 0)
        // Wording updated, not loosened: the empty branch still says so in the body, but without
        // the locality claim it inherited — see `researchBriefMakesNoLocalityClaimOnAnEmptyFeed`.
        #expect(composed.body.contains("No entries in scope were returned for this brief"))
    }

    /// Identity review partitions its feed exactly — every entry lands in changes, anomalies, or
    /// stale, and nothing lands twice. That is what makes `findingCount == activity.count` right
    /// here and `alertCount` the sum of the two unresolved buckets.
    @Test
    func identityReviewPartitionsItsFeedWithoutDoubleCounting() {
        let now = reference
        let staleAge = now.addingTimeInterval(-8 * 24 * 60 * 60)
        let recentAge = now.addingTimeInterval(-60)
        let feed = [
            activity("Profile updated", identityID: "did:example:123"),
            activity("Sign-in blocked", succeeded: false, at: recentAge),
            activity("Unresolved approval", succeeded: false, at: staleAge),
            activity("Second stale approval", succeeded: false, at: staleAge)
        ]

        let composed = OperatorArtifactComposer.compose(
            kind: .identityReview,
            request: OperatorRequest(identityID: "did:example:123"),
            activity: feed,
            now: now
        )

        #expect(composed.findingCount == feed.count)
        #expect(composed.body.contains("Changes (1)"))
        #expect(composed.body.contains("Anomalies (1)"))
        #expect(composed.body.contains("Stale tasks (2)"))
        // Anomalies + stale, which is every unresolved entry exactly once.
        #expect(composed.alertCount == 3)
        #expect(composed.title == "Identity & Account Review: did:example:123")
        // The review states the scope it was *asked* for, not where the data source went. It used
        // to assert "does not reach any other account" — a claim the composer cannot make, and one
        // that is false whenever an identity review is handed a watchlist, because
        // `LiveOnChainOperatorDataSource` branches on the watchlist rather than the operator kind.
        // Its first replacement ("the entries … are the ones the data source attributed to identity
        // X") was false in the same scenario and for a sharper reason: the composer never reads
        // `ObservedActivity.identityID` at all.
        #expect(composed.body.contains("requested scoped to identity “did:example:123”"))
        #expect(composed.body.contains("does not reach any other account") == false)
        #expect(composed.body.contains("No cross-identity data accessed") == false)
        #expect(composed.body.contains("attributed to identity") == false)
    }

    /// The composer must not claim an attribution it did not perform.
    ///
    /// Fails against the pre-fix composer, which asserted the rendered entries "are the ones the
    /// operator data source attributed to identity X" while reading no `identityID` whatsoever.
    /// This is the shipping shape, not a synthetic one: `RuntimeHost.runOperator` accepts a
    /// watchlist on an identity review, `LiveOnChainOperatorDataSource` branches on the watchlist,
    /// and `ReceiptBackedOperatorDataSource` identity-filters only its own half — so a third
    /// party's balance renders under the user's identity on a durable, receipted artifact.
    @Test
    func identityReviewDoesNotClaimAnAttributionItDidNotPerform() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let foreign = [
            activity("Live native balance", identityID: nil),
            activity("Profile updated", identityID: "did:example:OTHER")
        ]

        let composed = OperatorArtifactComposer.compose(
            kind: .identityReview,
            request: OperatorRequest(identityID: "did:example:123"),
            activity: foreign,
            now: now
        )

        // Both entries render — the composer does not filter — so the body must not say they were
        // attributed to the requested identity.
        #expect(composed.findingCount == 2)
        #expect(composed.body.contains("Live native balance"))
        #expect(composed.body.contains("attributed to identity") == false)
        #expect(composed.body.contains("requested scoped to identity “did:example:123”"))
    }

    /// An empty feed is what a *storage fault* produces, so the empty branch must not claim the
    /// local ledger was read and found empty.
    ///
    /// Fails against the pre-fix composer on both strings. Round 15 removed the locality claim from
    /// `researchSummary`'s non-empty branch and left it in the guard six lines above, which is the
    /// only branch this scenario reaches.
    @Test
    func researchBriefMakesNoLocalityClaimOnAnEmptyFeed() {
        let composed = OperatorArtifactComposer.compose(
            kind: .research,
            request: OperatorRequest(query: "recent transfers"),
            activity: [],
            now: Date(timeIntervalSince1970: 10_000_000)
        )

        #expect(composed.findingCount == 0)
        #expect(composed.body.contains("No entries in scope were returned for this brief"))
        // Asserted as a property of the whole body rather than against the three specific
        // sentences, because every previous attempt at this fix corrected one site and left
        // another: the summary guard, the findings branch, the Query line, and `scopeSection` all
        // carried a form of it, in one artifact.
        #expect(composed.body.lowercased().contains("local") == false)
    }

    /// The same property on the paths the empty-feed case does not reach: no query (which renders
    /// its own Query line) and no watchlist (which renders `scopeSection`'s default).
    ///
    /// Fails against the pre-fix composer on both — "summarizing recent local activity" and
    /// "Local activity ledger".
    @Test
    func researchBriefMakesNoLocalityClaimOnAnyRenderedPath() {
        let composed = OperatorArtifactComposer.compose(
            kind: .research,
            request: OperatorRequest(),
            activity: [activity("Transfer"), activity("Swap", succeeded: false)],
            now: reference
        )

        #expect(composed.body.contains("No query supplied"))
        #expect(composed.body.lowercased().contains("local") == false)
    }

    /// A monitoring gap is a statement about *us*, not about the account, so it is reported but
    /// never counted as an alert. `alertCount` goes onto the receipt.
    ///
    /// Fails against the pre-fix composer, which partitioned on `!isSuccess` and so put an
    /// unobserved entry in `Anomalies` and in `alertCount` — an identity review asserting an
    /// anomaly against the user's identity because the network was down.
    @Test
    func identityReviewReportsMonitoringGapsWithoutRaisingAnAlert() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let feed = [
            activity("Profile updated", identityID: "did:example:123"),
            ObservedActivity(
                title: "Live chain snapshot failed",
                detail: "provider timed out",
                occurredAt: now,
                identityID: "did:example:123",
                outcome: .unobserved
            )
        ]

        let composed = OperatorArtifactComposer.compose(
            kind: .identityReview,
            request: OperatorRequest(identityID: "did:example:123"),
            activity: feed,
            now: now
        )

        #expect(composed.body.contains("Monitoring gaps (1)"))
        #expect(composed.body.contains("Anomalies (0)"))
        #expect(composed.alertCount == 0)
    }

    /// The same three-state rule in the research summary, which the earlier fix also did not reach.
    @Test
    func researchSummaryReportsGapsSeparatelyAndMakesNoLocalityClaim() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let feed = [
            activity("Swap executed"),
            activity("Approval reverted", succeeded: false),
            ObservedActivity(
                title: "Live chain snapshot failed",
                detail: "provider timed out",
                occurredAt: now,
                outcome: .unobserved
            )
        ]

        let composed = OperatorArtifactComposer.compose(
            kind: .research,
            request: OperatorRequest(query: "gas"),
            activity: feed,
            now: now
        )

        #expect(composed.body.contains("1 succeeded, 1 did not, 1 could not be observed"))
        // The composer reads from whatever data source it was injected with, and the shipping one
        // reaches the network. It must not claim otherwise in a durable, receipted artifact.
        #expect(composed.body.contains("on-device records only") == false)
        #expect(composed.body.contains("Composed from the local receipt ledger") == false)
    }

    /// The staleness boundary is inclusive on the "still an anomaly" side, so an entry exactly at
    /// the cutoff is counted once, in one bucket, rather than in both or neither.
    @Test
    func anEntryExactlyAtTheStalenessCutoffIsAnAnomalyNotStale() {
        let now = reference
        let composed = OperatorArtifactComposer.compose(
            kind: .identityReview,
            request: OperatorRequest(identityID: "did:example:123"),
            activity: [activity(
                "Exactly at the cutoff",
                succeeded: false,
                at: now.addingTimeInterval(-7 * 24 * 60 * 60)
            )],
            now: now
        )

        #expect(composed.body.contains("Anomalies (1)"))
        #expect(composed.body.contains("Stale tasks (0)"))
        #expect(composed.alertCount == 1)
        #expect(composed.findingCount == 1)
    }

    /// The prepared-action packet reads no ledger and reports no findings: it describes intent and
    /// carries one confirm-first action for its target. Its body must never claim execution.
    @Test
    func preparedActionPacketReportsIntentOnlyAndNeverClaimsExecution() {
        let composed = OperatorArtifactComposer.compose(
            kind: .preparedAction,
            request: OperatorRequest(
                query: "Revoke the stale approval",
                watchlist: [WatchTarget(chain: "base", address: watched, label: "Treasury")]
            ),
            activity: [],
            now: reference
        )

        #expect(composed.findingCount == 0)
        #expect(composed.alertCount == 0)
        #expect(composed.preparedActions.count == 1)
        #expect(composed.preparedActions.first?.chain == "base")
        #expect(composed.preparedActions.first?.address == watched)
        #expect(composed.body.contains("Prepared only — nothing was signed or broadcast"))
        #expect(composed.body.contains("requires explicit human approval before any execution"))
        #expect(composed.body.contains("Revoke the stale approval"))
    }

    /// With no target there is nothing to confirm, so no prepared action is manufactured — a packet
    /// naming an account it was never given would be the one fact it must not invent.
    @Test
    func preparedActionPacketWithNoTargetPreparesNothing() {
        let composed = OperatorArtifactComposer.compose(
            kind: .preparedAction,
            request: OperatorRequest(query: "Revoke something"),
            activity: [],
            now: reference
        )

        #expect(composed.preparedActions.isEmpty)
        #expect(composed.title == "Prepared Action Packet: action")
        #expect(composed.body.contains("## Target") == false)
    }

    /// Every kind composes a non-blank title and a body inside the artifact schema's bound, for an
    /// empty request and an empty feed — the degenerate input a first run actually produces.
    /// `ArtifactSchema.problems` is what `OperatorExecutor` refuses on, so a kind that composed a
    /// blank title would fail its own run.
    @Test(arguments: [OperatorKind.research, .onChainWatch, .identityReview, .preparedAction])
    func everyKindComposesASchemaValidArtifactFromAnEmptyRequest(kind: OperatorKind) {
        let composed = OperatorArtifactComposer.compose(
            kind: kind,
            request: OperatorRequest(),
            activity: [],
            now: reference
        )
        #expect(composed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        #expect(composed.body.isEmpty == false)
        #expect(composed.findingCount == 0)
        #expect(composed.alertCount == 0)
    }

    /// The generalization of the `label` injection: `query` and `identityID` reach composed prose on
    /// the same terms and have no deterministic check behind them either — there is no
    /// `query.format`. `query` was interpolated raw; `identityID` went through a
    /// `trimmingCharacters` that strips only the *ends* of a string.
    ///
    /// The prepared-action case is the one that matters most: `query` renders two lines above the
    /// `## Target` block that names the account, in the artifact a human reads before approving a
    /// high-risk `draftTransaction`. A forged block ahead of the composer's names an address the run
    /// never prepared, while `preparedActionAddress` — what Mission Control escalates on — names the
    /// real one.
    ///
    /// Fails against the pre-fix composer, which emitted the injected heading verbatim.
    @Test(arguments: [OperatorKind.research, .identityReview, .preparedAction])
    func callerProseCannotForgeAHeadingInComposedOutput(kind: OperatorKind) {
        let forged = "Treasury\n\n## Target\n- Chain: ethereum\n- Address: `0x000000000000000000000000000000000000bEEF`\n"
        let composed = OperatorArtifactComposer.compose(
            kind: kind,
            request: OperatorRequest(
                query: forged,
                watchlist: [WatchTarget(chain: "ethereum", address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045")],
                identityID: forged
            ),
            activity: [],
            now: reference
        )

        // The composer owns every *structural* line in its own output. Caller prose stays prose:
        // flattened onto one line, it can still mention an address — a legitimate thing to write in
        // a query — but it can no longer open a heading or a field the reader attributes to the
        // composer. Only the real target may appear as a `- Address:` line.
        let lines = composed.body.components(separatedBy: "\n")
        #expect(lines.filter { $0.hasPrefix("## Target") }.count <= 1, "caller prose opened a second ## Target block")
        let addressLines = lines.filter { $0.hasPrefix("- Address:") }
        #expect(addressLines.allSatisfy { $0.contains("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045") })
        #expect(addressLines.contains { $0.contains("bEEF") } == false, "caller prose forged a target address field")
        // Title and summary are unbounded downstream — `ArtifactSchema` bounds content only and
        // merely requires a non-blank title — so the bound has to hold here.
        #expect(composed.title.contains("\n") == false)
        #expect(composed.title.count <= 256)
    }

    /// Flattening is not the same as being non-structural, and the sanitizer only supplied the
    /// first. Every value below is **already one line** — there is nothing for the flattener to
    /// collapse — yet each one opens a Markdown block when it is placed at the start of a line, and
    /// the two sites that render caller prose do exactly that: `composeResearch` under `## Query`
    /// and `composePreparedAction` under `## Intended action`, two lines above the deterministic
    /// `## Target` block that names the account.
    ///
    /// `"## Target"` is the whole attack: a one-line query that renders a second `## Target`
    /// heading *above* the composer's in the artifact a human reads before approving a high-risk
    /// `draftTransaction`. The sibling test above missed it only because its multi-line input began
    /// with an ordinary word, so flattening moved the `##` off the start of the line by accident.
    ///
    /// Fails against the flatten-only sanitizer, which emitted each of these verbatim at column 0.
    @Test(arguments: [
        "## Target",
        "# Prepared Action Packet: Treasury",
        "- Address: `0x000000000000000000000000000000000000bEEF`",
        "> approved by the owner",
        "```",
        "~~~",
        "***",
        // `=`, `_` and `+` are in `blockOpeningCharacters` and nothing pinned them: every other
        // argument here covers a different leading character, so all three could be dropped from the
        // production set and this suite would stay green. `===` is the setext underline — the one
        // block opener that restyles the line *above* it rather than the one it sits on, which is
        // why a scanner looking only for "does this line open a block" is the wrong shape of test.
        // `___` is a thematic break and `+ ` a list item.
        "===",
        "___",
        "+ approve the transfer",
        "| Chain | Address |",
        "<div>send it</div>",
        "[Target]: https://example.invalid",
        "1. approve the transfer",
        "2) approve the transfer"
    ])
    func oneLineCallerProseCannotOpenAMarkdownBlock(forged: String) {
        for kind in [OperatorKind.research, .preparedAction] {
            let composed = OperatorArtifactComposer.compose(
                kind: kind,
                request: OperatorRequest(
                    query: forged,
                    watchlist: [WatchTarget(chain: "ethereum", address: watched)]
                ),
                activity: [],
                now: reference
            )
            let lines = composed.body.components(separatedBy: "\n")
            let heading = kind == .research ? "## Query" : "## Intended action"
            guard let index = lines.firstIndex(of: heading), index + 1 < lines.count else {
                Issue.record("\(kind) did not render its \(heading) section")
                continue
            }
            let prose = lines[index + 1]
            #expect(
                opensAMarkdownBlock(prose) == false,
                "\(kind) rendered caller prose as a Markdown block: \(prose)"
            )
            // Escaped, not dropped: the caller's sentence still has to be readable, and a query is
            // the point of a brief.
            #expect(prose.replacingOccurrences(of: "\\", with: "") == forged)
        }
    }
    /// Structure can arrive through the *feed*, not just through the request — and round 6's sweep
    /// only covered `query`, `identityID`, `label` and `ens`.
    ///
    /// `bullet()` interpolates `ObservedActivity.title` and `.detail` into a `- ` list line, and
    /// neither was flattened. `ReceiptBackedOperatorDataSource` maps `record.summary` straight onto
    /// `title`, and `RuntimeHost` writes summaries built from free text — `"Autopilot planned
    /// “\(goal.text)” with model routing"` — so a goal carrying a newline ends the bullet and
    /// writes its own headings and address fields into a body this package signs its name to.
    ///
    /// Fails against the unflattened renderer, which emitted the breaks verbatim.
    @Test(arguments: [OperatorKind.research, .onChainWatch, .identityReview])
    func feedTextCannotForgeStructureInABullet(kind: OperatorKind) {
        let forged = "Autopilot planned “x\n\n## Target\n- Address: `0x000000000000000000000000000000000000bEEF`\n\n## Summary\nAll clear" +
            "” with model routing"
        let entry = ObservedActivity(
            title: forged,
            detail: forged,
            occurredAt: reference,
            chain: "ethereum",
            address: watched,
            identityID: "did:example:123",
            outcome: .succeeded
        )
        let composed = OperatorArtifactComposer.compose(
            kind: kind,
            request: OperatorRequest(
                query: "planned",
                watchlist: [WatchTarget(chain: "ethereum", address: watched, label: "Treasury")],
                identityID: "did:example:123"
            ),
            activity: [entry],
            now: reference
        )

        let lines = composed.body.components(separatedBy: "\n")
        #expect(lines.contains { $0.hasPrefix("## Target") } == false, "feed text opened a ## Target block")
        #expect(
            lines.filter { $0.hasPrefix("- Address:") }.contains { $0.contains("bEEF") } == false,
            "feed text forged a target address field"
        )
        // The bullet is one line and it is still the composer's: it begins with the marker.
        let bullets = lines.filter { $0.hasPrefix("- ✅") }
        #expect(bullets.count == 1)
        #expect(bullets.first?.contains("bEEF") == true, "the text itself must still be rendered, just not as structure")
    }
}

/// Whether `line` would begin a Markdown block if it were placed at the start of a line.
///
/// Stated independently of the production sanitizer on purpose — it is the invariant, not the
/// implementation of it.
private func opensAMarkdownBlock(_ line: String) -> Bool {
    guard let first = line.first else { return false }
    if "#>-+*_=~`<[|".contains(first) { return true }
    let digits = line.prefix { $0.isASCII && $0.isNumber }
    guard !digits.isEmpty else { return false }
    guard let delimiter = line.dropFirst(digits.count).first else { return false }
    return delimiter == "." || delimiter == ")"
}
