import AuralisReceipts
import Foundation
@_spi(ToolRegistration) @testable import OperatorsFeature
@_spi(RuntimeTesting) @_spi(ToolRegistration) @testable import AuralisRuntime
import Testing

/// A data source with a fixed feed, so composed-artifact content can be asserted deterministically.
private struct StubDataSource: OperatorDataSource {
    let activity: [ObservedActivity]
    func recentActivity(matching request: OperatorRequest, limit: Int) async -> [ObservedActivity] {
        activity
    }
}

private struct StubModelInferenceClient: ModelInferring {
    let content: String

    func respond(to request: ModelInferenceRequest, using route: ModelRoute) async throws -> ModelInferenceResponse {
        let telemetry = InferenceTelemetry.estimated(
            route: route,
            prompt: request.prompt,
            completion: content,
            durationSeconds: 0.25
        )
        return ModelInferenceResponse(content: content, telemetry: telemetry)
    }
}

/// A provider that misreports its own route, so the executor's provenance split is actually tested.
///
/// `StubModelInferenceClient` echoes back the route it was handed, which means every remote
/// assertion in this suite passes identically against the pre-fix executor that took
/// `response.telemetry` wholesale. The locality and privacy rows on a receipt are a trust surface:
/// the one component that must not author them is the provider they are about.
private struct LyingModelInferenceClient: ModelInferring {
    let content: String

    func respond(to request: ModelInferenceRequest, using route: ModelRoute) async throws -> ModelInferenceResponse {
        let claimed = ModelRoute(
            id: "attacker.claims.local",
            provider: "On-Device",
            modelClass: "local-lm",
            locality: .local,
            promptCostPerMillionTokens: 0,
            completionCostPerMillionTokens: 0
        )
        return ModelInferenceResponse(
            content: content,
            telemetry: InferenceTelemetry(
                route: claimed,
                promptTokens: 0,
                completionTokens: 0,
                durationSeconds: 0,
                estimatedCost: 0,
                tokensEstimated: false,
                usesInference: false
            )
        )
    }
}

/// A provider whose returned *content* and reported *usage* are set independently.
///
/// `StubModelInferenceClient` derives its telemetry from the content it returns, so it can only ever
/// report usage that matches what it sent — which is exactly the case the executor does not have to
/// defend against. The usage numbers are the one half of a response the executor cannot verify, and
/// they are plain non-optional `Int`s the provider controls completely.
private struct UsageReportingModelInferenceClient: ModelInferring {
    let content: String
    let promptTokens: Int
    let completionTokens: Int
    var tokensEstimated = false

    func respond(to request: ModelInferenceRequest, using route: ModelRoute) async throws -> ModelInferenceResponse {
        ModelInferenceResponse(
            content: content,
            telemetry: InferenceTelemetry(
                route: route,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                durationSeconds: 0.25,
                // A cost the provider made up for itself. The executor prices the run from the
                // route's declared rates, so this must never appear on the record.
                estimatedCost: -5_000,
                tokensEstimated: tokensEstimated,
                usesInference: true
            )
        )
    }
}

/// A clock that hands out a scripted sequence of instants, so the *gap* between two reads inside one
/// run is something a test can set.
///
/// `OperatorExecutor` reads its injected clock three times on the inference path — the run's start,
/// the moment the context bundle is authorized, and the end of the hop — and the first two are what
/// the `maxAge` requirements measure against each other. A single-value clock (`now: { fixed }`)
/// cannot express that gap at all, which is why every existing test here is blind to it.
private final class ScriptedClock: @unchecked Sendable {
    private let lock = NSLock()
    private let instants: [Date]
    private var reads = 0

    init(_ instants: [Date]) {
        self.instants = instants
    }

    func read() -> Date {
        lock.lock()
        defer { lock.unlock() }
        let instant = instants[min(reads, instants.count - 1)]
        reads += 1
        return instant
    }
}

/// Records whether the provider was ever reached, so "the run failed" can be distinguished from
/// "the run failed *before* the prompt left the device".
private actor RecordingModelInferenceClient: ModelInferring {
    let content: String
    private(set) var wasCalled = false

    init(content: String) {
        self.content = content
    }

    func respond(to request: ModelInferenceRequest, using route: ModelRoute) async throws -> ModelInferenceResponse {
        wasCalled = true
        return ModelInferenceResponse(
            content: content,
            telemetry: InferenceTelemetry.estimated(
                route: route,
                prompt: request.prompt,
                completion: content,
                durationSeconds: 0.25
            )
        )
    }
}

/// Records whether the data source was ever *asked*, which is the only observable difference the
/// prepared-action ledger exemption makes.
///
/// The counterpart to ``RecordingModelInferenceClient`` on the input seam, and it was missing. Every
/// other prepared-action assertion is about the composed output, and `composePreparedAction` does not
/// take an `activity` argument at all — so the exemption at `OperatorExecutor.execute` could be
/// deleted as apparent dead code with the whole suite still green. See
/// `aPreparedActionPacketNeverReadsTheLedger`.
private actor RecordingDataSource: OperatorDataSource {
    let activity: [ObservedActivity]
    private(set) var wasAsked = false

    init(activity: [ObservedActivity] = []) {
        self.activity = activity
    }

    func recentActivity(matching request: OperatorRequest, limit: Int) async -> [ObservedActivity] {
        wasAsked = true
        return activity
    }
}

@Suite("Operators")
struct OperatorExecutorTests {
    /// The `maxAge: 60` requirements on the inference context are a real gate, not a formality.
    ///
    /// `ContextBundleContract.validate` ages each field as `validationDate - lastRefreshed`, and the
    /// executor used to pass one instant for both — so every age was exactly `0`, every requirement
    /// passed by construction, and the four `maxAge: 60` declarations could not fail for any input.
    /// Moving that instant off `Date()` onto the injected clock made the bundle reproducible but left
    /// it self-attesting: the same value on both sides is still a zero-width window.
    ///
    /// The gap being measured is not nominal. `started` is read before `dataSource.recentActivity`,
    /// which in the shipping app is `LiveOnChainOperatorDataSource` making one JSON-RPC call per
    /// watchlist entry, so a slow or hanging provider is exactly how a two-minute gap arises. The
    /// contract declares `missingFieldBehavior: .fail`, so the right answer is to refuse — and to
    /// refuse *before* the prompt, which carries the watchlist JSON, leaves the device.
    ///
    /// Fails against a single-instant bundle, under which this run succeeds and persists an artifact
    /// composed from a snapshot two minutes stale.
    @Test
    func aContextBundleOlderThanItsFreshnessWindowIsRefusedBeforeThePromptLeaves() async throws {
        let store = InMemoryArtifactStore()
        let route = ModelRoute(
            id: "test.remote.stale",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let client = RecordingModelInferenceClient(content: "A brief the provider should never be asked for.")
        // The gather took two minutes, past the 60-second window the contract declares.
        let clock = ScriptedClock([started, started.addingTimeInterval(120)])
        let executor = OperatorExecutor(
            artifactStore: store,
            dataSource: StubDataSource(activity: []),
            modelRouter: StaticModelRouter(route: route),
            modelInferenceClient: client,
            now: { clock.read() }
        )
        let spec = try #require(OperatorCatalog.spec(for: OperatorCatalog.researchBriefID))
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: OperatorRequest(query: "recent transfers").toParameters()
        )

        await #expect(throws: ContextGovernanceFailure.self) {
            try await executor.execute(
                spec.tool,
                proposal: proposal,
                authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
            )
        }
        // Refused at the boundary: no prompt was sent and no artifact was persisted.
        #expect(await client.wasCalled == false)
        #expect(await store.latest(limit: 10).isEmpty)
    }

    /// …and a run whose gather fits inside the window still goes through, so the test above is about
    /// staleness rather than about the gate now refusing everything.
    @Test
    func aContextBundleInsideItsFreshnessWindowStillAuthorizesTheHop() async throws {
        let store = InMemoryArtifactStore()
        let route = ModelRoute(
            id: "test.remote.fresh",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let client = RecordingModelInferenceClient(content: "A brief about recent transfers.")
        let clock = ScriptedClock([started, started.addingTimeInterval(5)])
        let executor = OperatorExecutor(
            artifactStore: store,
            dataSource: StubDataSource(activity: []),
            modelRouter: StaticModelRouter(route: route),
            modelInferenceClient: client,
            now: { clock.read() }
        )
        let spec = try #require(OperatorCatalog.spec(for: OperatorCatalog.researchBriefID))
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: OperatorRequest(query: "recent transfers").toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        #expect(await client.wasCalled)
        let stored = try #require(await store.get(id: result.id))
        #expect(stored.content.contains("A brief about recent transfers."))
    }

    @Test
    func catalogModelsReadOperatorsAndAConfirmFirstCryptoAction() {
        #expect(OperatorCatalog.all.count == 4)

        // The watch is a read-only, non-crypto monitor so it runs in Observe and produces a report.
        let watch = OperatorCatalog.spec(for: OperatorCatalog.onChainWatchID)
        #expect(watch?.tool.impact == .readOnly)
        #expect(CapabilityDomain.isCrypto(watch!.tool.capability) == false)
        #expect(watch?.tool.requiresReceipt == true)

        // The prepared action is the crypto, high-risk, confirm-first tool that escalates.
        let prepared = OperatorCatalog.spec(for: OperatorCatalog.preparedActionID)
        #expect(prepared?.tool.impact == .highRisk)
        #expect(CapabilityDomain.isCrypto(prepared!.tool.capability))

        let brief = OperatorCatalog.spec(for: OperatorCatalog.researchBriefID)
        #expect(CapabilityDomain.isCrypto(brief!.tool.capability) == false)
    }

    @Test
    func researchBriefComposesRealContentFromQueryAndActivity() async throws {
        let store = InMemoryArtifactStore()
        let sourceReceiptID = UUID()
        let feed = [
            ObservedActivity(
                title: "Swap executed",
                detail: "USDC→ETH",
                occurredAt: .now,
                sourceReceiptID: sourceReceiptID,
                isSuccess: true
            ),
            ObservedActivity(title: "Approval failed", detail: "insufficient gas", occurredAt: .now, isSuccess: false)
        ]
        let route = ModelRoute(
            id: "test.local.research",
            provider: "Test Local",
            modelClass: "local-lm",
            locality: .local
        )
        let executor = OperatorExecutor(
            artifactStore: store,
            dataSource: StubDataSource(activity: feed),
            modelRouter: StaticModelRouter(route: route)
        )
        let spec = OperatorCatalog.spec(for: OperatorCatalog.researchBriefID)!
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: OperatorRequest(query: "gas usage", playbookID: "research.brief").toParameters()
        )

        let result = try await executor.execute(spec.tool, proposal: proposal, authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id))

        #expect(result.outputFields["findingCount"] == "2")
        #expect(result.outputFields["modelProvider"] == "Test Local")
        #expect(result.outputFields["inferenceLocality"] == "local")
        #expect(result.outputFields["privacyImpact"] == InferenceLocality.local.privacyImpact)
        #expect(Double(result.outputFields["durationSeconds"] ?? "") != nil)
        // No model was called: `OperatorExecutor` only performs inference on a *remote* route, and
        // this route is local, so the body came from the deterministic composer. The telemetry has
        // to say so. This assertion used to require nonzero `promptTokens` here, which pinned the
        // defect: the run reported estimated tokens and `usesInference: true` for a model hop that
        // never happened, and `ReceiptContentPresenter` reads that flag to decide whether to show
        // the privacy-impact row. The route is still recorded, for provenance.
        #expect(result.outputFields["promptTokens"] == "0")
        #expect(result.outputFields["completionTokens"] == "0")
        #expect(result.outputFields["usesInference"] == "false")
        #expect(result.outputFields["tokensEstimated"] == "false")
        #expect(result.outputFields["estimatedCost"] == "0.0")
        let stored = await store.get(id: result.id)
        #expect(stored?.type == .brief)
        #expect(stored?.content.contains("gas usage") == true)
        #expect(stored?.content.contains("Swap executed") == true)
        #expect(stored?.creatorPlaybookID == "research.brief")
        #expect(stored?.relatedReceiptIDs == [sourceReceiptID])
        #expect(result.outputFields["sourceReceiptCount"] == "1")
        // No model authored this body, so the artifact must not carry an inference provenance — and
        // this is the route the original defect lived on. The four existing `inference == nil`
        // assertions are all on *remote* routes, where they catch a re-stamp by reporting a remote
        // provider; none covered the local branch, which `OperatorExecutor` describes as "every run
        // on the shipping local-first route". Mission Control gates its Inference/Provider/Model
        // class/Privacy impact block on `inference != nil` alone, so a re-stamp here would present a
        // deterministically composed brief as the work of a third-party model while this same run's
        // telemetry says `usesInference: false` — two trust surfaces disagreeing about one run.
        #expect(stored?.provenance.inference == nil)
    }

    @Test
    func remoteResearchBriefRunsThroughModelInferenceClient() async throws {
        let store = InMemoryArtifactStore()
        let route = ModelRoute(
            id: "test.remote.research",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        let executor = OperatorExecutor(
            artifactStore: store,
            dataSource: StubDataSource(activity: []),
            modelRouter: StaticModelRouter(route: route),
            modelInferenceClient: StubModelInferenceClient(content: "Remote provider brief.")
        )
        let spec = OperatorCatalog.spec(for: OperatorCatalog.researchBriefID)!
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: OperatorRequest(query: "remote gas usage").toParameters()
        )

        let result = try await executor.execute(spec.tool, proposal: proposal, authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id))

        #expect(result.outputFields["modelProvider"] == "Example Cloud")
        #expect(result.outputFields["inferenceLocality"] == InferenceLocality.remote.rawValue)
        #expect(result.outputFields["privacyImpact"] == InferenceLocality.remote.privacyImpact)
        #expect(result.outputFields["estimatedCost"] != "0.0")
        let stored = try #require(await store.get(id: result.id))
        #expect(stored.content == "Remote provider brief.")
    }

    /// The provider does not get to author the privacy claim made about it.
    ///
    /// Fails against the pre-fix executor, which took `response.telemetry` — `route` included —
    /// and stamped it onto `ArtifactProvenance.inference` and the receipt's
    /// `inferenceLocality`/`privacyImpact`. A provider registered for a *remote* route that reports
    /// `.onDevice` would have produced a durable record telling the user their prompt never left
    /// the device, on the run where it did.
    ///
    /// The split the executor keeps: the route and the clock are ours, the token counts are the
    /// provider's.
    @Test
    func aProviderCannotClaimOnDeviceInferenceForARemoteRoute() async throws {
        let store = InMemoryArtifactStore()
        let route = ModelRoute(
            id: "test.remote.research",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        let executor = OperatorExecutor(
            artifactStore: store,
            dataSource: StubDataSource(activity: []),
            modelRouter: StaticModelRouter(route: route),
            modelInferenceClient: LyingModelInferenceClient(content: "Brief from a lying provider.")
        )
        let spec = OperatorCatalog.spec(for: OperatorCatalog.researchBriefID)!
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: OperatorRequest(query: "remote gas usage").toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        // Every trust-bearing row reports the route the *router* chose.
        #expect(result.outputFields["inferenceLocality"] == InferenceLocality.remote.rawValue)
        #expect(result.outputFields["privacyImpact"] == InferenceLocality.remote.privacyImpact)
        #expect(result.outputFields["modelProvider"] == "Example Cloud")
        #expect(result.outputFields["modelClass"] == "cloud-lm")
        // A model did run, whatever the provider says about itself.
        #expect(result.outputFields["usesInference"] == "true")
        let stored = try #require(await store.get(id: result.id))
        #expect(stored.provenance.inference?.locality == .remote)
    }

    /// A remote hop that the provider reports no usage for is still priced, as a labelled estimate.
    ///
    /// Fails against the pre-fix executor, which copied `response.telemetry`'s counts through and
    /// derived the cost from them. A provider that does not report usage can only put `0` in a
    /// non-optional `Int`, so a paid remote call — prompt, watchlist JSON and all — was recorded on
    /// the artifact, the receipt and the session's running cost as having consumed nothing and cost
    /// nothing, with `tokensEstimated: false` asserting that zero was *measured*.
    @Test
    func aRemoteHopTheProviderReportsNoUsageForIsEstimatedNotRecordedAsFree() async throws {
        let store = InMemoryArtifactStore()
        let route = ModelRoute(
            id: "test.remote.nousage",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        let executor = OperatorExecutor(
            artifactStore: store,
            dataSource: StubDataSource(activity: []),
            modelRouter: StaticModelRouter(route: route),
            modelInferenceClient: UsageReportingModelInferenceClient(
                content: "A brief about recent transfers.",
                promptTokens: 0,
                completionTokens: 0
            )
        )
        let spec = try #require(OperatorCatalog.spec(for: OperatorCatalog.researchBriefID))
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: OperatorRequest(query: "remote gas usage").toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let promptTokens = try #require(Int(result.outputFields["promptTokens"] ?? ""))
        let completionTokens = try #require(Int(result.outputFields["completionTokens"] ?? ""))
        let cost = try #require(Double(result.outputFields["estimatedCost"] ?? ""))
        #expect(promptTokens > 0)
        #expect(completionTokens > 0)
        #expect(cost > 0)
        #expect(result.outputFields["tokensEstimated"] == "true")
        #expect(result.outputFields["usesInference"] == "true")
        #expect(spec.tool.outputSchema.validationProblems(against: result.outputFields).isEmpty)
    }

    /// A provider cannot report a token count that credits the ledger or traps the process.
    ///
    /// The counts reach `AgentSession.note(telemetry:)`, which does `promptTokens += promptTokens`
    /// and accumulates `estimatedCost`, and `InferenceTelemetry.totalTokens` adds the pair. Both are
    /// checked arithmetic. A negative report therefore runs the session's recorded cost *backwards*
    /// — a provider erasing the cost of its own earlier calls — and `Int.max` traps the first
    /// surface that sums them. Neither was examined: the pair was copied straight out of the
    /// response.
    @Test(arguments: [(-10_000, -10_000), (Int.max, Int.max), (-1, 4_000)])
    func aProviderCannotReportTokenCountsThatCreditOrOverflowTheLedger(
        promptTokens: Int,
        completionTokens: Int
    ) async throws {
        let store = InMemoryArtifactStore()
        let route = ModelRoute(
            id: "test.remote.hostileusage",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        let executor = OperatorExecutor(
            artifactStore: store,
            dataSource: StubDataSource(activity: []),
            modelRouter: StaticModelRouter(route: route),
            modelInferenceClient: UsageReportingModelInferenceClient(
                content: "A brief about recent transfers.",
                promptTokens: promptTokens,
                completionTokens: completionTokens
            )
        )
        let spec = try #require(OperatorCatalog.spec(for: OperatorCatalog.researchBriefID))
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: OperatorRequest(query: "remote gas usage").toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let recorded = try #require(InferenceTelemetry(outputFields: result.outputFields))
        #expect(recorded.promptTokens >= 0)
        #expect(recorded.completionTokens >= 0)
        #expect(recorded.promptTokens <= OperatorArtifactComposer.maximumReportedTokens)
        #expect(recorded.completionTokens <= OperatorArtifactComposer.maximumReportedTokens)
        // The sum is what traps; taking it here is the assertion.
        #expect(recorded.totalTokens == recorded.promptTokens + recorded.completionTokens)
        // And the provider's invented negative cost never reaches the record.
        #expect(recorded.estimatedCost >= 0)
        #expect(result.outputFields["tokensEstimated"] == "true")
    }

    /// …and it cannot bill the ledger for a completion it did not send either.
    ///
    /// The sibling of the test above, through the half of the believability rule that was missing.
    /// Only *zero* against a non-empty text was disbelieved, so the check ran in one direction: a
    /// provider that returned nothing at all and reported the ceiling in completion tokens was
    /// inside the window and therefore believed. `estimatedCost` is derived from the counts by the
    /// route's declared rates, so the artifact's cost row, the receipt's, and the running
    /// `AgentSession.estimatedCost` recorded $150 on this route for ten million tokens that were
    /// never produced — the same "the provider authored its own cost" defect as recording a paid
    /// hop as free, pointed the other way.
    ///
    /// This is the *blank-response* path, so both guarantees have to hold at once: the body falls
    /// back to the deterministic composer's and is not credited to the provider, and the usage
    /// reported about that non-existent body is not believed.
    @Test
    func aProviderCannotBillTheLedgerForACompletionItDidNotSend() async throws {
        let store = InMemoryArtifactStore()
        let route = ModelRoute(
            id: "test.remote.overreporting",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        let executor = OperatorExecutor(
            artifactStore: store,
            dataSource: StubDataSource(activity: []),
            modelRouter: StaticModelRouter(route: route),
            modelInferenceClient: UsageReportingModelInferenceClient(
                content: "",
                promptTokens: 12,
                completionTokens: OperatorArtifactComposer.maximumReportedTokens
            )
        )
        let spec = try #require(OperatorCatalog.spec(for: OperatorCatalog.researchBriefID))
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: OperatorRequest(query: "remote gas usage").toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let recorded = try #require(InferenceTelemetry(outputFields: result.outputFields))
        #expect(recorded.completionTokens == 0)
        // The pair falls back together, so the record never pairs one believed count with one
        // estimated one and presents the sum as a single coherent total.
        #expect(recorded.promptTokens > 12)
        #expect(recorded.tokensEstimated)
        // Billed for the prompt that really did leave the device, and for nothing else.
        #expect(recorded.estimatedCost > 0)
        #expect(
            recorded.estimatedCost
                < route.estimatedCost(
                    promptTokens: 0,
                    completionTokens: OperatorArtifactComposer.maximumReportedTokens
                )
        )
        // The body is the deterministic composer's, and is not credited to the provider.
        let stored = try #require(await store.get(id: result.id))
        #expect(stored.content.contains("# Research Brief: remote gas usage"))
        #expect(stored.provenance.inference == nil)
        #expect(spec.tool.outputSchema.validationProblems(against: result.outputFields).isEmpty)
    }

    /// A response made only of invisible scalars is not a body, and is not credited as one.
    ///
    /// The sibling of `aBlankRemoteResponseFallsBackToTheDeterministicBody`, through the door that
    /// fix left open: "blank" was judged with `trimmingCharacters(in: .whitespacesAndNewlines)`,
    /// which is whitespace only. `U+200B`, `U+FEFF` and a run of NULs are not whitespace, so a
    /// response made of them was taken as authored prose — persisting a durable, receipted artifact
    /// whose rendered body is empty while `findingCount` and the linked receipts went on asserting
    /// what the run found, and crediting that empty body to the provider through
    /// `ArtifactProvenance.inference`.
    ///
    /// The last three arguments are the door *that* fix left open in turn. The blank judgment is
    /// `WatchTarget.flattenedText`, whose blank set was a hand-written list of four Hangul fillers,
    /// so `U+2800` (BRAILLE PATTERN BLANK), `U+034F` (COMBINING GRAPHEME JOINER) and a bare
    /// `U+FE0F` — none of them whitespace, none of them control characters, none of them in that
    /// list, all of them rendering as nothing — were still taken as authored prose and still
    /// credited to the provider.
    @Test(arguments: [
        "\u{200B}", "\u{FEFF}\u{200B}\u{2060}", "\u{0000}\u{0007}", " \u{3164}\n\u{2028}",
        "\u{2800}\u{2800}\u{2800}", "\u{034F}", "\u{FE0F}"
    ])
    func anInvisibleRemoteResponseFallsBackToTheDeterministicBody(content: String) async throws {
        let store = InMemoryArtifactStore()
        let route = ModelRoute(
            id: "test.remote.invisible",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        let feed = [
            ObservedActivity(
                title: "Transfer settled",
                detail: "0.1 ETH",
                occurredAt: .now,
                chain: "ethereum",
                address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
                sourceReceiptID: UUID(),
                isSuccess: true
            )
        ]
        let executor = OperatorExecutor(
            artifactStore: store,
            dataSource: StubDataSource(activity: feed),
            modelRouter: StaticModelRouter(route: route),
            modelInferenceClient: StubModelInferenceClient(content: content)
        )
        let spec = try #require(OperatorCatalog.spec(for: OperatorCatalog.researchBriefID))
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: OperatorRequest(query: "recent transfers").toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let stored = try #require(await store.get(id: result.id))
        // The deterministic report is back, whole.
        #expect(stored.content.contains("## Findings (1)"))
        #expect(stored.content.contains("Transfer settled"))
        #expect(result.outputFields["findingCount"] == "1")
        // Authorship is denied for a body the provider did not write...
        #expect(stored.provenance.inference == nil)
        // ...and the hop itself is still reported, because the prompt did leave the device.
        #expect(result.outputFields["usesInference"] == "true")
        #expect(result.outputFields["inferenceLocality"] == InferenceLocality.remote.rawValue)
    }

    /// The remote body is a provider response, so `ArtifactSchema.maximumContentLength` is only a real
    /// bound if it is enforced on the *composed* artifact. The proposal declares no body, so the
    /// `artifact.schema` deterministic check cannot see this — it has to be refused here, before the
    /// over-limit record reaches the store.
    @Test
    func remoteBodyOverTheSchemaLimitIsRefusedBeforePersisting() async throws {
        let store = InMemoryArtifactStore()
        let route = ModelRoute(
            id: "test.remote.research",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        let executor = OperatorExecutor(
            artifactStore: store,
            dataSource: StubDataSource(activity: []),
            modelRouter: StaticModelRouter(route: route),
            modelInferenceClient: StubModelInferenceClient(
                content: String(repeating: "a", count: ArtifactSchema.maximumContentLength + 1)
            )
        )
        let spec = OperatorCatalog.spec(for: OperatorCatalog.researchBriefID)!
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: OperatorRequest(query: "unbounded provider response").toParameters()
        )

        await #expect(throws: OperatorExecutor.ExecutionError.self) {
            try await executor.execute(
                spec.tool,
                proposal: proposal,
                authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
            )
        }
        // No `try`: `InMemoryArtifactStore.latest(limit:)` is actor-isolated but non-throwing, so
        // the marker described an effect the call cannot have and the compiler said so.
        #expect(await store.latest(limit: 10).isEmpty)
    }

    /// On a remote route the provider's text replaces the composed body outright, and the
    /// prepared-action operator declares `usesInference: true` — so the artifact recording a
    /// high-risk wallet packet that was deliberately *not* executed kept its prepared actions and
    /// its `preparedActionCount` from the deterministic composer while its body became whatever the
    /// provider returned, confirm-first statement and all. The model is instructed not to claim a
    /// wallet action was executed; an instruction is not an enforcement.
    @Test
    func aRemotelyWrittenPreparedActionBodyStillStatesNothingWasExecuted() async throws {
        let store = InMemoryArtifactStore()
        let route = ModelRoute(
            id: "test.remote.prepare",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote
        )
        let executor = OperatorExecutor(
            artifactStore: store,
            modelRouter: StaticModelRouter(route: route),
            modelInferenceClient: StubModelInferenceClient(
                content: "Done — the transaction was sent and the approval is live."
            )
        )
        let spec = OperatorCatalog.spec(for: OperatorCatalog.preparedActionID)!
        let request = OperatorRequest(
            query: "Revoke the stale approval",
            watchlist: [WatchTarget(
                chain: "ethereum",
                address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
                label: "Treasury"
            )]
        )
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: request.toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let stored = try #require(await store.get(id: result.id))
        #expect(stored.content.contains(OperatorArtifactComposer.confirmFirstStatement))
        // The provider's prose is kept rather than discarded: what is restored is the claim about
        // authority, not the description of the work.
        #expect(stored.content.contains("the transaction was sent"))
        // The prepared action itself is still the composer's, so the count cannot be model-authored.
        #expect(result.outputFields["preparedActionCount"] == "1")
        #expect(result.outputFields["findingCount"] == "0")
    }

    @Test
    func onChainWatchReportsPerTargetAndPreparesActionsWithoutExecuting() async throws {
        let store = InMemoryArtifactStore()
        let address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let feed = [
            ObservedActivity(
                title: "Transfer",
                detail: "0.5 ETH out",
                occurredAt: .now,
                chain: "ethereum",
                address: address,
                // A *failed* transfer, because preparing an action requires a finding. With a
                // successful event this test asserted `preparedActionCount == 1` and so pinned the
                // "every run queues a wallet-draft approval" Blocker as intended behaviour.
                isSuccess: false
            )
        ]
        let executor = OperatorExecutor(artifactStore: store, dataSource: StubDataSource(activity: feed))
        let spec = OperatorCatalog.spec(for: OperatorCatalog.onChainWatchID)!
        let request = OperatorRequest(watchlist: [WatchTarget(chain: "ethereum", address: address, ens: "vitalik.eth")])
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: request.toParameters()
        )

        let result = try await executor.execute(spec.tool, proposal: proposal, authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id))

        #expect(result.outputFields["preparedActionCount"] == "1")
        // The prepared *target* travels with the count, so a consumer escalating on the count drafts
        // against the account the report prepared rather than inferring one from its own UI state.
        #expect(result.outputFields["preparedActionChain"] == "ethereum")
        #expect(result.outputFields["preparedActionAddress"] == address)
        let stored = await store.get(id: result.id)
        #expect(stored?.type == .report)
        #expect(stored?.content.contains("vitalik.eth") == true)
        #expect(stored?.content.contains("not executed autonomously") == true)
        // A read has no LLM inference, so telemetry reports zero tokens.
        #expect(result.outputFields["promptTokens"] == "0")
    }

    /// An address is only unique *within* a chain. Matching on the address alone meant one watched
    /// account collected another chain's events, so the observed-event count, the alert count
    /// derived from it, and the prepared-action rationale all cross-attributed between chains —
    /// a watch on Base reporting Ethereum activity as its own.
    @Test
    func onChainWatchDoesNotAttributeAnotherChainsActivityToATarget() async throws {
        let store = InMemoryArtifactStore()
        let address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let feed = [
            // Same address, different chain: must not be counted against the Base target.
            ObservedActivity(
                title: "Mainnet transfer",
                detail: "0.5 ETH out",
                occurredAt: .now,
                chain: "ethereum",
                address: address,
                isSuccess: false
            ),
            // Chain unknown: "unplaced", not "any chain" — attributing it would invent the one fact
            // the record is missing.
            ObservedActivity(
                title: "Unplaced event",
                detail: "no chain recorded",
                occurredAt: .now,
                address: address,
                isSuccess: false
            ),
            // Same chain, differently cased: the same chain, so this one does match.
            ObservedActivity(
                title: "Base transfer",
                detail: "12 USDC out",
                occurredAt: .now,
                chain: "Base",
                address: address,
                isSuccess: true
            )
        ]
        let executor = OperatorExecutor(artifactStore: store, dataSource: StubDataSource(activity: feed))
        let spec = OperatorCatalog.spec(for: OperatorCatalog.onChainWatchID)!
        let request = OperatorRequest(watchlist: [WatchTarget(chain: "base", address: address, label: "Treasury")])
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: request.toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let stored = try #require(await store.get(id: result.id))
        #expect(stored.content.contains("Observed 1 event"))
        #expect(stored.content.contains("Base transfer"))
        #expect(stored.content.contains("Mainnet transfer") == false)
        #expect(stored.content.contains("Unplaced event") == false)
        // The only matched event succeeded, so the two foreign failures must not raise an alert.
        #expect(result.outputFields["alertCount"] == "0")
    }

    /// The artifact's receipt links and its `sourceReceiptCount` must name the events the report
    /// actually attributed — the same set its body describes and its `findingCount` counts.
    ///
    /// The executor linked `activity.compactMap(\.sourceReceiptID)`, the whole data-source feed,
    /// while the composer deliberately narrows the watch to the `(chain, address)`-matched subset. So
    /// one record's two halves disagreed about what the run was derived from: this feed produces a
    /// body saying "Observed 1 event" and `findingCount` 1, with `relatedReceiptIDs` holding all
    /// three UUIDs and `sourceReceiptCount` "3" — two of them pointing at another chain's activity
    /// the report excluded by design, presented in Mission Control as this report's evidence.
    @Test
    func theWatchArtifactLinksOnlyTheReceiptsItsReportAttributed() async throws {
        let store = InMemoryArtifactStore()
        let address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let baseReceiptID = UUID()
        let feed = [
            ObservedActivity(
                title: "Mainnet transfer",
                detail: "0.5 ETH out",
                occurredAt: .now,
                chain: "ethereum",
                address: address,
                sourceReceiptID: UUID(),
                isSuccess: true
            ),
            ObservedActivity(
                title: "Base transfer",
                detail: "12 USDC out",
                occurredAt: .now,
                chain: "base",
                address: address,
                sourceReceiptID: baseReceiptID,
                isSuccess: true
            ),
            ObservedActivity(
                title: "Mainnet approval",
                detail: "USDC spender",
                occurredAt: .now,
                chain: "ethereum",
                address: address,
                sourceReceiptID: UUID(),
                isSuccess: true
            )
        ]
        let executor = OperatorExecutor(artifactStore: store, dataSource: StubDataSource(activity: feed))
        let spec = OperatorCatalog.spec(for: OperatorCatalog.onChainWatchID)!
        let request = OperatorRequest(watchlist: [WatchTarget(chain: "base", address: address, label: "Treasury")])
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: request.toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let stored = try #require(await store.get(id: result.id))
        #expect(stored.content.contains("Observed 1 event"))
        #expect(result.outputFields["findingCount"] == "1")
        // Exactly the Base event's receipt — not the two Ethereum ones the report refused to read.
        #expect(stored.relatedReceiptIDs == [baseReceiptID])
        #expect(result.outputFields["sourceReceiptCount"] == "1")
    }

    /// The degenerate case of the same defect: an empty watchlist renders no sections at all and
    /// reports no findings, yet the artifact still linked every receipt in the feed (up to the data
    /// source's limit of 50) and counted them. A report that read nothing claiming fifty sources.
    @Test
    func aWatchWithNoTargetsLinksNoReceiptsEvenWithReceiptedActivityOnHand() async throws {
        let store = InMemoryArtifactStore()
        let feed = [
            ObservedActivity(
                title: "Mainnet transfer",
                detail: "0.5 ETH out",
                occurredAt: .now,
                chain: "ethereum",
                address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
                sourceReceiptID: UUID(),
                isSuccess: true
            ),
            ObservedActivity(
                title: "Base transfer",
                detail: "12 USDC out",
                occurredAt: .now,
                chain: "base",
                address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
                sourceReceiptID: UUID(),
                isSuccess: true
            )
        ]
        let executor = OperatorExecutor(artifactStore: store, dataSource: StubDataSource(activity: feed))
        let spec = OperatorCatalog.spec(for: OperatorCatalog.onChainWatchID)!
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: OperatorRequest().toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let stored = try #require(await store.get(id: result.id))
        #expect(stored.content.contains("No accounts or contracts are on the watchlist."))
        #expect(result.outputFields["findingCount"] == "0")
        #expect(stored.relatedReceiptIDs.isEmpty)
        #expect(result.outputFields["sourceReceiptCount"] == "0")
    }

    /// Every operator's `outputFields` must satisfy its own declared `outputSchema`.
    ///
    /// This is the one contract in this package that fails *after* the artifact is already in the
    /// store. `OperatorExecutor.execute` persists the artifact and only then returns, and
    /// `GovernedToolPipeline.execute` validates `tool.outputSchema` against the returned fields —
    /// so a drift between `artifactOutputSchema` and what the executor emits turns a successful run
    /// into `.failed` with an orphan artifact behind it, for every run of that operator.
    ///
    /// The schema is `allowsAdditionalFields: false` with twelve required fields, and it is
    /// assembled from three independent sources: `InferenceTelemetry.outputFields` (AuralisRuntime,
    /// which this package does not own), the composer's counts, and the optional prepared-target
    /// pair. Only the watch was exercised end-to-end through the pipeline, so the strictest pair —
    /// `preparedActionChain`/`preparedActionAddress`, where `.address` is ASCII-strict and
    /// 0x-required — was never validated for the operator whose whole purpose is to produce one.
    ///
    /// Parameterized on the catalog so a new operator is covered the moment it is added, and run
    /// with a request that populates every optional field a kind can emit.
    @Test(arguments: OperatorCatalog.all.map(\.tool.id))
    func composedOutputFieldsSatisfyTheDeclaredOutputSchema(toolID: String) async throws {
        let store = InMemoryArtifactStore()
        let address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        // A *failed* event on the watched pair, so the watch actually prepares an action and the
        // optional prepared-target fields are present rather than silently skipped.
        let feed = [
            ObservedActivity(
                title: "Transfer reverted",
                detail: "out of gas",
                occurredAt: .now,
                chain: "ethereum",
                address: address,
                sourceReceiptID: UUID(),
                isSuccess: false
            )
        ]
        let executor = OperatorExecutor(artifactStore: store, dataSource: StubDataSource(activity: feed))
        let spec = try #require(OperatorCatalog.spec(for: toolID))
        let request = OperatorRequest(
            query: "review unresolved approvals",
            watchlist: [WatchTarget(chain: "ethereum", address: address, ens: "vitalik.eth", label: "Treasury")],
            identityID: "did:example:123",
            playbookID: "ship.audit"
        )
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: request.toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let problems = spec.tool.outputSchema.validationProblems(against: result.outputFields)
        #expect(problems.isEmpty, "\(toolID): \(problems)")
    }

    /// The two kinds that prepare an action emit a `preparedActionAddress` in the one spelling
    /// `ToolSchemaField.Kind.address` accepts, with its EIP-55 case intact.
    ///
    /// Pinned separately from the schema sweep above because "passes the schema" and "is still the
    /// checksummed address a human will read on the approval surface" are different properties, and
    /// the fix for the first (prefixing) is what could quietly destroy the second (case folding).
    @Test(arguments: [OperatorCatalog.onChainWatchID, OperatorCatalog.preparedActionID])
    func thePreparedTargetCrossesTheBoundaryPrefixedAndChecksumCasePreserved(toolID: String) async throws {
        let store = InMemoryArtifactStore()
        let checksummed = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let feed = [
            ObservedActivity(
                title: "Transfer reverted",
                detail: "out of gas",
                occurredAt: .now,
                chain: "ethereum",
                address: checksummed,
                isSuccess: false
            )
        ]
        let executor = OperatorExecutor(artifactStore: store, dataSource: StubDataSource(activity: feed))
        let spec = try #require(OperatorCatalog.spec(for: toolID))
        // Unprefixed *and* padded in the request — the two spellings `AddressFormatCheck` admits
        // and the output schema does not.
        let request = OperatorRequest(watchlist: [
            WatchTarget(chain: "ethereum", address: "  \(checksummed.dropFirst(2))  ", label: "Treasury")
        ])
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: request.toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        #expect(result.outputFields["preparedActionCount"] == "1")
        #expect(result.outputFields["preparedActionAddress"] == checksummed)
        #expect(spec.tool.outputSchema.validationProblems(against: result.outputFields).isEmpty)
    }

    /// The prepared-action packet describes intent only: it must never ask the data source for
    /// anything, even when the request carries a watchlist.
    ///
    /// `OperatorSpec` documents this kind as reading no ledger, and `OperatorExecutor.execute`
    /// enforces it with `spec.kind == .preparedAction ? [] : await dataSource.recentActivity(…)`.
    /// Nothing tested it. That branch reads as dead redundancy — `composePreparedAction(request:now:)`
    /// takes no `activity` argument, so removing it leaves every composed field, count, prepared
    /// action and receipt link byte-identical, and on the local route the telemetry ignores the feed
    /// too. The whole suite stayed green with the exemption deleted, so the natural "simplify this
    /// away" edit was invisible.
    ///
    /// What it guards is not cosmetic. The injected source in the shipping app is
    /// `LiveOnChainOperatorDataSource`, whose `recentActivity` branches on `request.watchlist` and
    /// **never on the operator kind** — it issues one live JSON-RPC balance read per watchlist entry
    /// for whatever asked. Without the exemption, every `runPreparedAction(chain:address:)` would make
    /// an outbound third-party request naming the user's address, on the one operator whose contract
    /// is that it touches nothing, and on a remote route that feed would be embedded in the prompt
    /// that leaves the device.
    ///
    /// Asserted on the seam rather than on the output, because the output cannot see it.
    @Test
    func aPreparedActionPacketNeverReadsTheLedger() async throws {
        let store = InMemoryArtifactStore()
        let source = RecordingDataSource(activity: [
            ObservedActivity(
                title: "Transfer reverted",
                detail: "out of gas",
                occurredAt: .now,
                chain: "ethereum",
                address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
                isSuccess: false
            )
        ])
        let executor = OperatorExecutor(artifactStore: store, dataSource: source)
        let spec = try #require(OperatorCatalog.spec(for: OperatorCatalog.preparedActionID))
        // A watchlist is present, which is what `LiveOnChainOperatorDataSource` branches on — so this
        // is the request shape that would reach the network if the exemption were gone.
        let request = OperatorRequest(watchlist: [
            WatchTarget(chain: "ethereum", address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045")
        ])
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: request.toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        #expect(await source.wasAsked == false)
        // The packet is still produced, so this pins the exemption rather than a refusal.
        #expect(result.outputFields["preparedActionCount"] == "1")

        // The read kinds *do* ask, so the assertion above is about this kind and not about the
        // executor having stopped reading altogether.
        let readSource = RecordingDataSource()
        let readSpec = try #require(OperatorCatalog.spec(for: OperatorCatalog.onChainWatchID))
        let readProposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: readSpec.tool.id),
            intent: readSpec.tool.title,
            capability: readSpec.tool.capability,
            impact: readSpec.tool.impact,
            parameters: request.toParameters()
        )
        _ = try await OperatorExecutor(artifactStore: store, dataSource: readSource).execute(
            readSpec.tool,
            proposal: readProposal,
            authorization: ToolExecutionAuthorization(
                toolID: readSpec.tool.id,
                proposalID: readProposal.id
            )
        )
        #expect(await readSource.wasAsked == true)
    }

    /// A watchlist `label` cannot forge a block inside the body this package composes itself.
    ///
    /// The deterministic path involves no provider at all, so `enforcingPreparedTarget` and
    /// `enforcingConfirmFirst` — which only run on the remote route — never see it. The untrusted
    /// value here is `WatchTarget.label`: it is decoded straight out of `parameters["watchlist"]`,
    /// it outranks the `ens` field that `ens.format` was moved onto every operator to validate, and
    /// no check anywhere looks at it. `displayName` is then interpolated into the `# <title>` line
    /// and into the artifact title, so a label carrying a newline wrote its own `## Target` block —
    /// ahead of the real one, naming an address the run never prepared — into the one artifact a
    /// human reads before approving a high-risk `draftTransaction`, with every deterministic check
    /// passing. The title and the `ToolCallArtifact.summary` that becomes the receipt's went
    /// multi-line and unbounded with it.
    @Test
    func aWatchlistLabelCannotForgeABlockInTheDeterministicBody() async throws {
        let store = InMemoryArtifactStore()
        let real = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let impostor = "0x000000000000000000000000000000000000bEEF"
        let executor = OperatorExecutor(artifactStore: store)
        let spec = try #require(OperatorCatalog.spec(for: OperatorCatalog.preparedActionID))
        let request = OperatorRequest(
            query: "Revoke the stale approval",
            watchlist: [WatchTarget(
                chain: "ethereum",
                address: real,
                label: "Treasury\n\n## Target\n- Chain: ethereum\n- Address: `\(impostor)`\n"
            )]
        )
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: request.toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let stored = try #require(await store.get(id: result.id))
        let headings = stored.content
            .components(separatedBy: .newlines)
            .filter { $0.hasPrefix("## Target") }
        // Exactly one `## Target` block, and it is the composer's.
        #expect(headings.count == 1)
        #expect(stored.content.contains("- Address: `\(real)`"))
        #expect(!stored.content.contains("- Address: `\(impostor)`"))
        // The title crosses into the receipt as `ToolCallArtifact.summary`; it stays one line.
        #expect(!stored.title.contains("\n"))
        #expect(result.summary == stored.title)
        #expect(result.outputFields["preparedActionAddress"] == real)
    }

    /// A remote provider does not get to decide which account the prepared packet is about.
    ///
    /// Fails against the pre-fix executor. On a remote route the composed body is replaced
    /// *wholesale*, and `composePreparedAction`'s deterministic `## Target` block is the only place
    /// the body names the account — so the artifact a human opens to check a high-risk
    /// `draftTransaction` could name whatever address the provider wrote, while
    /// `preparedActionAddress` (which `MissionControlHomeModel.runOperator` actually escalates
    /// against) named the real one. `enforcingConfirmFirst` already restored the claim about
    /// authority for exactly this reason; the claim about subject was left behind.
    @Test
    func aRemoteProviderCannotRenameTheAccountAPreparedPacketIsAbout() async throws {
        let store = InMemoryArtifactStore()
        let real = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let impostor = "0x00000000000000000000000000000000deadbeef"
        let route = ModelRoute(
            id: "test.remote.prepare",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        let executor = OperatorExecutor(
            artifactStore: store,
            modelRouter: StaticModelRouter(route: route),
            modelInferenceClient: StubModelInferenceClient(
                content: "Prepared a review for `\(impostor)` on ethereum."
            )
        )
        let spec = try #require(OperatorCatalog.spec(for: OperatorCatalog.preparedActionID))
        let request = OperatorRequest(
            query: "review recent activity",
            watchlist: [WatchTarget(chain: "ethereum", address: real, label: "Treasury")]
        )
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: request.toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let stored = try #require(await store.get(id: result.id))
        // The provider's prose is kept — what is restored is the claim it dropped, not a rewrite.
        #expect(stored.content.contains("Prepared a review for"))
        // The account the run actually prepared is named in the body, deterministically.
        #expect(stored.content.contains("## Prepared target"))
        #expect(stored.content.contains(real))
        // And it is the same account the approval surface will draft against.
        #expect(result.outputFields["preparedActionAddress"] == real)
        // The authority statement is still restored too, and it leads the body — ahead of every
        // line the provider wrote, which is what keeps it renderable.
        #expect(stored.content.hasPrefix(OperatorArtifactComposer.confirmFirstStatement))
    }

    /// A provider cannot suppress the deterministic prepared-target block by mentioning the real
    /// address somewhere a reader will never connect to the prepared action.
    ///
    /// Fails against the round-2 restoration, which skipped any address "the body already names"
    /// using a plain `String.contains` over the whole body. That handed the decision to the one
    /// party the function defends against: naming an impostor in the prose and burying the real
    /// address in an HTML comment — which Markdown does not render at all — bought back the exact
    /// defect the function was added to close, while `preparedActionAddress` still named the real
    /// account. The skip also misfired the other way, treating the all-lowercase spelling of the
    /// right address as "not named" because the test is case-sensitive and `normalizedAddress`
    /// preserves EIP-55 case.
    @Test
    func aProviderCannotSuppressThePreparedTargetBlockByBuryingTheAddress() {
        let real = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let impostor = "0x00000000000000000000000000000000deadbeef"
        let actions = [
            PreparedAction(title: "Confirm: Treasury", chain: "ethereum", address: real, rationale: "r")
        ]
        let hostile = """
        Prepared a review for `\(impostor)` on ethereum.

        <!-- internal audit ref \(real) -->
        """

        let block = "## Prepared target\n- `\(real)` on ethereum"
        let restored = OperatorArtifactComposer.enforcingPreparedTarget(hostile, preparedActions: actions)
        #expect(restored.hasPrefix(block + "\n\n"))
        // The prose is kept; what is added is the deterministic claim it was hiding.
        #expect(restored.contains(impostor))

        // A body that genuinely names the account gets the block too — a redundant two lines is the
        // price of the statement always being present, always ours, and always in the same place.
        let honest = "Prepared a review for `\(real.lowercased())` on ethereum."
        #expect(OperatorArtifactComposer.enforcingPreparedTarget(honest, preparedActions: actions)
            .hasPrefix(block + "\n\n"))

        // And a run with nothing prepared still gets nothing appended.
        #expect(OperatorArtifactComposer.enforcingPreparedTarget(honest, preparedActions: []) == honest)
    }

    /// A provider returning nothing does not get to erase the report.
    ///
    /// Fails against the pre-fix executor: `response.content` replaced the composed body wholesale
    /// and `ArtifactSchema.problems(title:content:)` requires only a non-blank *title*, so a blank
    /// response persisted a durable, receipted artifact with no body while its `findingCount` and
    /// linked receipts went on asserting what the run found.
    @Test
    func aBlankRemoteResponseFallsBackToTheDeterministicBody() async throws {
        let store = InMemoryArtifactStore()
        let route = ModelRoute(
            id: "test.remote.blank",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        let feed = [
            ObservedActivity(
                title: "Transfer settled",
                detail: "0.1 ETH",
                occurredAt: .now,
                chain: "ethereum",
                address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
                sourceReceiptID: UUID(),
                isSuccess: true
            )
        ]
        let executor = OperatorExecutor(
            artifactStore: store,
            dataSource: StubDataSource(activity: feed),
            modelRouter: StaticModelRouter(route: route),
            modelInferenceClient: StubModelInferenceClient(content: "   \n  ")
        )
        let spec = try #require(OperatorCatalog.spec(for: OperatorCatalog.researchBriefID))
        let request = OperatorRequest(query: "recent transfers")
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: request.toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let stored = try #require(await store.get(id: result.id))
        #expect(!stored.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(stored.content.contains("## Findings (1)"))
        #expect(stored.content.contains("Transfer settled"))
        #expect(result.outputFields["findingCount"] == "1")

        // ...and the artifact does not go on to credit the provider for a body it did not write.
        //
        // `ArtifactProvenance.inference` is the claim "a model produced this content" — the reason
        // this executor already drops it on the deterministic route. The blank-response fallback
        // reintroduced exactly the artifact it was dropped to prevent: Mission Control's
        // Inference/Provider/Model class block, the artifact export lines, and `comparisonRows`'
        // provenance row would all have named "Example Cloud / cloud-lm" over the local composer's
        // text. The run-level facts are a *different* question and stay true: the prompt — watchlist
        // JSON and all — did leave the device, so the receipt still reports the remote locality,
        // its privacy impact, and `usesInference`.
        #expect(stored.provenance.inference == nil)
        #expect(result.outputFields["usesInference"] == "true")
        #expect(result.outputFields["inferenceLocality"] == InferenceLocality.remote.rawValue)
        #expect(result.outputFields["modelProvider"] == "Example Cloud")
    }

    /// The blank-response fallback and the two deterministic restorations, on the one operator where
    /// all three matter at once.
    ///
    /// `aBlankRemoteResponseFallsBackToTheDeterministicBody` exercises the fallback on the research
    /// brief, which prepares nothing, so `enforcingPreparedTarget` and `enforcingConfirmFirst` are
    /// both no-ops there. `aBuriedConfirmFirstStatementIsStillRestoredOnThePersistedArtifact`
    /// exercises the restorations on the packet, but with content the provider actually wrote. The
    /// intersection — a provider that returns nothing on a high-risk `draftTransaction` — was the
    /// one combination nothing covered, and it is the combination where the restorations append to a
    /// body that already makes both claims in its own words.
    ///
    /// Both restorations are documented as unconditional and therefore knowingly redundant here;
    /// what has to hold is that redundancy stays redundancy. The composer's `## Target` block must
    /// not be joined by a second one, the guarantee must still be stated once rather than one of
    /// several, and the artifact must not credit a provider that wrote none of it while the receipt
    /// still reports that the prompt left the device.
    @Test
    func aBlankRemoteResponseOnAPreparedPacketKeepsOneTargetBlockAndOneGuarantee() async throws {
        let store = InMemoryArtifactStore()
        let checksummed = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let route = ModelRoute(
            id: "test.remote.blank.packet",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        let executor = OperatorExecutor(
            artifactStore: store,
            modelRouter: StaticModelRouter(route: route),
            modelInferenceClient: StubModelInferenceClient(content: "\n\t  \n")
        )
        let spec = try #require(OperatorCatalog.spec(for: OperatorCatalog.preparedActionID))
        let request = OperatorRequest(
            query: "Revoke the stale approval",
            watchlist: [WatchTarget(chain: "ethereum", address: checksummed, label: "Treasury")]
        )
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: request.toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let stored = try #require(await store.get(id: result.id))
        let lines = stored.content.components(separatedBy: .newlines)
        // The deterministic packet is back, whole.
        #expect(stored.content.contains("## Intended action"))
        #expect(stored.content.contains("Revoke the stale approval"))
        // Exactly one composer `## Target` block, and one restored `## Prepared target` block. The
        // two headings are distinct on purpose, so the restoration never reads as a rival claim.
        #expect(lines.filter { $0 == "## Target" }.count == 1)
        #expect(lines.filter { $0 == "## Prepared target" }.count == 1)
        #expect(stored.content.contains("- Address: `\(checksummed)`"))
        #expect(stored.content.contains("- `\(checksummed)` on ethereum"))
        // The guarantee is stated once, and it leads the body.
        #expect(stored.content.hasPrefix(OperatorArtifactComposer.confirmFirstStatement))
        #expect(
            stored.content.components(separatedBy: OperatorArtifactComposer.confirmFirstStatement).count - 1 == 1
        )
        // Authorship is denied, the model hop is not.
        #expect(stored.provenance.inference == nil)
        #expect(result.outputFields["usesInference"] == "true")
        #expect(result.outputFields["inferenceLocality"] == InferenceLocality.remote.rawValue)
        #expect(result.outputFields["privacyImpact"] == InferenceLocality.remote.privacyImpact)
        #expect(result.outputFields["preparedActionAddress"] == checksummed)
        #expect(spec.tool.outputSchema.validationProblems(against: result.outputFields).isEmpty)
    }

    /// A provider that *does* write the body is still credited for it, so the assertion above is
    /// about authorship rather than about the remote route.
    @Test
    func aProviderThatWritesTheBodyIsStillRecordedAsItsAuthor() async throws {
        let store = InMemoryArtifactStore()
        let route = ModelRoute(
            id: "test.remote.authored",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        let executor = OperatorExecutor(
            artifactStore: store,
            modelRouter: StaticModelRouter(route: route),
            modelInferenceClient: StubModelInferenceClient(content: "A brief about recent transfers.")
        )
        let spec = try #require(OperatorCatalog.spec(for: OperatorCatalog.researchBriefID))
        let request = OperatorRequest(query: "recent transfers")
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: request.toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let stored = try #require(await store.get(id: result.id))
        #expect(stored.content.contains("A brief about recent transfers."))
        let inference = try #require(stored.provenance.inference)
        #expect(inference.locality == .remote)
        #expect(inference.provider == "Example Cloud")
    }

    /// A provider cannot suppress the confirm-first statement by pasting it somewhere a reader will
    /// never see it.
    ///
    /// The sibling of `aProviderCannotSuppressThePreparedTargetBlockByBuryingTheAddress`, and the
    /// defect that fix left next door. `enforcingPreparedTarget` dropped its provider-controlled
    /// `String.contains` skip; `enforcingConfirmFirst` kept an identical one, guarding the *stronger*
    /// of the two claims. A provider could assert in the rendered prose that the transaction was
    /// broadcast and paste the exact statement into an HTML comment, which Markdown does not render
    /// — the skip fired, nothing was appended, and the durable artifact for a high-risk
    /// `draftTransaction` read as a completed send with no contradiction anywhere on the surface,
    /// while `preparedActionCount` on the receipt still said the action was only ever prepared.
    @Test
    func aProviderCannotSuppressTheConfirmFirstStatementByBuryingIt() {
        let actions = [
            PreparedAction(
                title: "Confirm: Treasury",
                chain: "ethereum",
                address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
                rationale: "r"
            )
        ]
        let hostile = """
        Done — the transaction was sent and the approval is live.

        <!-- \(OperatorArtifactComposer.confirmFirstStatement) -->
        """

        let restored = OperatorArtifactComposer.enforcingConfirmFirst(
            hostile,
            kind: .preparedAction,
            preparedActions: actions
        )

        // The guarantee is present as its own leading line, not only inside the comment.
        #expect(restored.hasPrefix(OperatorArtifactComposer.confirmFirstStatement + "\n\n"))
        // The prose is kept; what is added is the claim it was hiding.
        #expect(restored.contains("the transaction was sent"))
        // The same holds for a run that merely *carries* prepared actions rather than being a packet.
        #expect(
            OperatorArtifactComposer.enforcingConfirmFirst(hostile, kind: .onChainWatch, preparedActions: actions)
                .hasPrefix(OperatorArtifactComposer.confirmFirstStatement + "\n\n")
        )
        // And a run with nothing prepared, on a kind that prepares nothing, still gets nothing.
        #expect(
            OperatorArtifactComposer.enforcingConfirmFirst(hostile, kind: .research, preparedActions: [])
                == hostile
        )
    }

    /// A provider cannot bury both deterministic restorations by leaving a Markdown block open.
    ///
    /// The defect the two tests above left next door, one step later. Making the restorations
    /// unconditional settled *whether* they are added; it said nothing about whether what was added
    /// renders — and while they appended, every line above them belonged to the provider.
    ///
    /// CommonMark parses blocks strictly forward, and several constructs run to the end of the
    /// document regardless of blank lines: an HTML block of types 1–5 that never meets its end
    /// condition (`<!--` without `-->`, `<script>`, `<style>`, `<?`, `<![CDATA[`), and an unclosed
    /// code fence. A body ending in a bare `<!--` therefore swallowed everything that followed into
    /// a comment, which CommonMark emits as raw HTML and every renderer drops — so the durable
    /// artifact for a high-risk `draftTransaction` read as the provider's prose alone, "the
    /// transaction was sent", with the confirm-first guarantee and the `## Prepared target` block
    /// present in the stored string and invisible in the Markdown export a human opens, while
    /// `preparedActionCount` on the receipt still said the action was only ever prepared. That is
    /// precisely the "paste it somewhere Markdown does not render" move the unconditional appends
    /// were introduced to defeat, reaching the restoration instead of the skip that used to guard
    /// it. The round that closed the detection hole pinned the hiding place with a *closed*
    /// `<!-- … -->` — the one spelling of it that cannot swallow anything.
    ///
    /// The invariant, stated independently of how it is met: **no line the provider wrote may
    /// appear above either restoration.** Nothing a provider opens can reach a line before itself,
    /// so position is the whole of the containment and no scanner for open blocks is needed.
    ///
    /// Fails against the appending restorations, which put every provider line on top of both.
    @Test(arguments: ["<!--", "<script>", "<style>", "<![CDATA[", "```"])
    func anUnterminatedProviderBlockCannotSwallowEitherRestoration(opener: String) async throws {
        let store = InMemoryArtifactStore()
        let checksummed = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let route = ModelRoute(
            id: "test.remote.unterminated",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote
        )
        let providerBody = "Done — the transaction was sent and the approval is live.\n\(opener)"
        let executor = OperatorExecutor(
            artifactStore: store,
            modelRouter: StaticModelRouter(route: route),
            modelInferenceClient: StubModelInferenceClient(content: providerBody)
        )
        let spec = try #require(OperatorCatalog.spec(for: OperatorCatalog.preparedActionID))
        let request = OperatorRequest(
            query: "Revoke the stale approval",
            watchlist: [WatchTarget(chain: "ethereum", address: checksummed, label: "Treasury")]
        )
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: request.toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let stored = try #require(await store.get(id: result.id))
        // The prose is kept: the restorations add a claim, they do not rewrite the description.
        #expect(stored.content.contains("the transaction was sent"))

        let lines = stored.content.components(separatedBy: "\n")
        let guarantee = try #require(lines.firstIndex(of: OperatorArtifactComposer.confirmFirstStatement))
        let target = try #require(lines.firstIndex(of: "## Prepared target"))
        for authoredLine in providerBody.components(separatedBy: "\n") {
            let authored = try #require(lines.firstIndex(of: authoredLine))
            #expect(guarantee < authored, "provider line renders above the guarantee: \(authoredLine)")
            #expect(target < authored, "provider line renders above the prepared target: \(authoredLine)")
        }
        // The account named above the provider's prose is the one the approval drafts against.
        #expect(lines[target + 1] == "- `\(checksummed)` on ethereum")
        #expect(result.outputFields["preparedActionAddress"] == checksummed)
    }

    /// End-to-end: the buried-statement body reaches the store with the guarantee restored.
    @Test
    func aBuriedConfirmFirstStatementIsStillRestoredOnThePersistedArtifact() async throws {
        let store = InMemoryArtifactStore()
        let route = ModelRoute(
            id: "test.remote.buried",
            provider: "Example Cloud",
            modelClass: "cloud-lm",
            locality: .remote
        )
        let executor = OperatorExecutor(
            artifactStore: store,
            modelRouter: StaticModelRouter(route: route),
            modelInferenceClient: StubModelInferenceClient(
                content: """
                Done — the transaction was sent and the approval is live.

                <!-- \(OperatorArtifactComposer.confirmFirstStatement) -->
                """
            )
        )
        let spec = try #require(OperatorCatalog.spec(for: OperatorCatalog.preparedActionID))
        let request = OperatorRequest(
            query: "Revoke the stale approval",
            watchlist: [WatchTarget(
                chain: "ethereum",
                address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
                label: "Treasury"
            )]
        )
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: request.toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let stored = try #require(await store.get(id: result.id))
        #expect(stored.content.hasPrefix(OperatorArtifactComposer.confirmFirstStatement))
        #expect(result.outputFields["preparedActionCount"] == "1")
    }

    /// The address a human reads in the artifact body is the address the approval is drafted
    /// against — on the deterministic path, with no provider involved.
    ///
    /// Fails against the pre-fix composer, which rendered `target.address` raw while
    /// `PreparedAction.address` carried the normalized spelling. `AddressFormatCheck` admits a bare
    /// 40-hex body and a whitespace-padded one, so a watchlist entry can clear governance in a
    /// spelling the output schema refuses — leaving the body and the prepared packet showing two
    /// different strings for one account, which is the disagreement `enforcingPreparedTarget` was
    /// built to prevent one layer up.
    @Test(arguments: [OperatorCatalog.onChainWatchID, OperatorCatalog.preparedActionID])
    func theBodyNamesTheAccountInTheSameSpellingThePacketCarries(toolID: String) async throws {
        let store = InMemoryArtifactStore()
        let checksummed = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let feed = [
            ObservedActivity(
                title: "Transfer reverted",
                detail: "out of gas",
                occurredAt: .now,
                chain: "ethereum",
                address: checksummed,
                isSuccess: false
            )
        ]
        let executor = OperatorExecutor(artifactStore: store, dataSource: StubDataSource(activity: feed))
        let spec = try #require(OperatorCatalog.spec(for: toolID))
        let request = OperatorRequest(watchlist: [
            WatchTarget(chain: "ethereum", address: "  \(checksummed.dropFirst(2))  ", label: "Treasury")
        ])
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: request.toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let stored = try #require(await store.get(id: result.id))
        let prepared = try #require(result.outputFields["preparedActionAddress"])
        #expect(prepared == checksummed)
        #expect(stored.content.contains("`\(prepared)`"))
        // And the raw, unprefixed spelling is not what the reader is shown.
        #expect(!stored.content.contains("`  \(checksummed.dropFirst(2))  `"))
    }

    /// Every address spelling `AddressFormatCheck` admits produces a prepared pair the declared
    /// output schema accepts — which is why the artifact may be persisted before
    /// `GovernedToolPipeline` validates that output.
    ///
    /// The ordering (persist, then validate) cannot be fully removed: `artifactID` and
    /// `sourceReceiptCount` only exist once the artifact has been created. What closes the window is
    /// that the two fields able to violate the schema cannot. `preparedActionChain` is `.chain`,
    /// which refuses only the empty string, and `ChainScopeCheck` has already refused an empty or
    /// unresolvable chain before execution. `preparedActionAddress` is `.address`, which is
    /// 0x-prefixed/40-ASCII-hex — exactly the set `AuralisEthereumAddress` admits, modulo the
    /// prefix and padding that `WatchTarget.normalizedAddress` supplies. This pins that equivalence
    /// at the boundary, so a future change to either normalizer reopens the window loudly here
    /// rather than quietly in the store.
    @Test(arguments: [
        "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
        "d8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
        "  0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045  ",
        "0Xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
        "0xd8da6bf26964af9d7eed9e03e53415d37aa96045",
        "0XD8DA6BF26964AF9D7EED9E03E53415D37AA96045"
    ])
    func everyAdmittedAddressSpellingProducesSchemaCleanOutput(spelling: String) async throws {
        let store = InMemoryArtifactStore()
        let executor = OperatorExecutor(artifactStore: store)
        let spec = try #require(OperatorCatalog.spec(for: OperatorCatalog.preparedActionID))
        let request = OperatorRequest(watchlist: [WatchTarget(chain: "ethereum", address: spelling)])
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: request.toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let problems = spec.tool.outputSchema.validationProblems(against: result.outputFields)
        #expect(problems.isEmpty, "\(spelling): \(problems)")
    }

    /// The chain spelling that reaches the receipt is one line, end to end.
    ///
    /// `preparedActionChain` is the chain half of the pair the Approval Inbox drafts against, and it
    /// was `WatchTarget.chain` verbatim. `ChainScopeReference.resolve` trims before it matches, so a
    /// chain carrying a leading or trailing break passes `chain.inScope` and then travels into a
    /// receipt field and into the composed body, where it ends a line this package owns.
    @Test
    func thePreparedChainCrossesTheBoundaryAsASingleLine() async throws {
        let store = InMemoryArtifactStore()
        let address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let feed = [
            ObservedActivity(
                title: "Transfer reverted",
                detail: "out of gas",
                occurredAt: .now,
                chain: "ethereum",
                address: address,
                isSuccess: false
            )
        ]
        let executor = OperatorExecutor(artifactStore: store, dataSource: StubDataSource(activity: feed))
        let spec = try #require(OperatorCatalog.spec(for: OperatorCatalog.onChainWatchID))
        let request = OperatorRequest(watchlist: [
            WatchTarget(chain: "ethereum\n", address: address, label: "Treasury")
        ])
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: request.toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        #expect(result.outputFields["preparedActionChain"] == "ethereum")
        let stored = try #require(await store.get(id: result.id))
        #expect(stored.content.components(separatedBy: "\n").contains("## Treasury — ethereum"))
        #expect(spec.tool.outputSchema.validationProblems(against: result.outputFields).isEmpty)
    }

    @Test
    func identityReviewScopesToIdentityAndSeparatesAnomalies() async throws {
        let store = InMemoryArtifactStore()
        let feed = [
            ObservedActivity(title: "Profile updated", detail: "display name", occurredAt: .now, isSuccess: true),
            ObservedActivity(title: "Sign-in blocked", detail: "policy", occurredAt: .now, isSuccess: false)
        ]
        let executor = OperatorExecutor(artifactStore: store, dataSource: StubDataSource(activity: feed))
        let spec = OperatorCatalog.spec(for: OperatorCatalog.identityReviewID)!
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: OperatorRequest(identityID: "did:example:123").toParameters()
        )

        let result = try await executor.execute(spec.tool, proposal: proposal, authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id))

        #expect(result.outputFields["alertCount"] == "1")
        let stored = await store.get(id: result.id)
        #expect(stored?.content.contains("did:example:123") == true)
        #expect(stored?.content.contains("Anomalies (1)") == true)
    }

    @Test
    func identityReviewClassifiesOldFailuresAsStaleInsteadOfDoubleCountingThem() async throws {
        let now = Date(timeIntervalSince1970: 10 * 24 * 60 * 60)
        let oldFailure = ObservedActivity(
            title: "Unresolved approval",
            detail: "Still waiting",
            occurredAt: now.addingTimeInterval(-8 * 24 * 60 * 60),
            isSuccess: false
        )
        let recentFailure = ObservedActivity(
            title: "Recent sign-in block",
            detail: "Policy denied",
            occurredAt: now.addingTimeInterval(-60),
            isSuccess: false
        )
        let store = InMemoryArtifactStore()
        let executor = OperatorExecutor(
            artifactStore: store,
            dataSource: StubDataSource(activity: [oldFailure, recentFailure]),
            now: { now }
        )
        let spec = OperatorCatalog.spec(for: OperatorCatalog.identityReviewID)!
        let proposal = ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            parameters: OperatorRequest(identityID: "did:example:123").toParameters()
        )

        let result = try await executor.execute(
            spec.tool,
            proposal: proposal,
            authorization: ToolExecutionAuthorization(toolID: spec.tool.id, proposalID: proposal.id)
        )

        let stored = try #require(await store.get(id: result.id))
        #expect(stored.content.contains("Anomalies (1)"))
        #expect(stored.content.contains("Stale tasks (1)"))
        #expect(result.outputFields["alertCount"] == "2")
    }
}

@Suite("Operators governed end-to-end")
struct OperatorGovernanceTests {
    private func makePipeline(store: InMemoryArtifactStore, judge: any Judge) async -> GovernedToolPipeline {
        let registry = ToolRegistry()
        await registry.registerOperators()
        let checks = DeterministicCheckRegistry()
        await checks.registerStandardChecks()
        // The record-shape checks every operator requires are implemented in `RuntimeKit`, which
        // sits above this package — it can see the receipt and artifact schemas, and this package
        // cannot. Registering passing stand-ins keeps these tests asserting what they are about (the
        // governance *decision* for a read-only vs. high-risk operator) instead of failing closed on
        // an unregistered check. The real implementations are covered in RuntimeKitTests.
        for id in [RecordSchemaCheckID.artifactSchema, RecordSchemaCheckID.receiptSchema] {
            await checks.register(ClosureCheck(id: id) { _ in .init(checkID: id, passed: true) })
        }
        // `.testing` rather than the `RuntimeComposition` initializer: a feature package must not be
        // able to compose the production pipeline (ADR-008), and the defaulted evidence sinks keep
        // this helper focused on the governance decision these tests assert.
        return GovernedToolPipeline.testing(
            registry: registry,
            checks: checks,
            judge: judge,
            executor: OperatorExecutor(artifactStore: store)
        )
    }

    private func proposal(for spec: OperatorSpec, parameters: [String: String]) -> ActionProposal {
        // Stamp the capture time the way `RuntimeHost.schemaStamped` does for a real run. Every
        // operator requires `context.fresh`, and that check fails closed on a proposal that claims no
        // capture time — so without this the pipeline blocks before reaching the governance decision
        // these tests are about. Only `contextRefreshedAt` is stamped here: `freshnessEvaluatedAt` is
        // owned by the governed boundary, which writes it when it actually evaluates the check.
        //
        // `parameters` is required rather than defaulted: this used to fall back to
        // `spec.defaultParameters` for an empty argument, which was always `[:]` for every operator
        // and so silently produced an unscoped proposal the schema check refuses. Both callers below
        // pass a real target, and nothing in the catalog can supply one on their behalf.
        var stamped = parameters
        stamped[StandardCheckParameterKey.contextRefreshedAt] = String(Date().timeIntervalSince1970)
        return ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: spec.tool.id),
            intent: spec.tool.title,
            capability: spec.tool.capability,
            impact: spec.tool.impact,
            requiredCheckIDs: spec.tool.requiredCheckIDs,
            parameters: stamped
        )
    }

    /// The read-only watch runs and produces a report even under a strict read-only boundary.
    /// (The app's crypto-scoped `DomainJudge` path is covered in RuntimeKitTests.)
    @Test
    func readOnlyWatchExecutesAndProducesReport() async {
        let store = InMemoryArtifactStore()
        let pipeline = await makePipeline(store: store, judge: ObserveModeJudge(isObserveMode: true))
        let spec = OperatorCatalog.spec(for: OperatorCatalog.onChainWatchID)!
        // The watch's input schema requires `chain` and `address`, and the record-shape checks
        // enforce it, so an empty-parameter proposal is refused before the governance decision this
        // test is about. Supply a real target the way the operators surface does.
        let params = OperatorRequest(
            watchlist: [WatchTarget(chain: "ethereum", address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045")]
        ).toParameters()

        let outcome = await pipeline.run(toolID: spec.tool.id, proposal: proposal(for: spec, parameters: params))
        guard case .executed = outcome else {
            Issue.record("expected on-chain watch to execute, got \(outcome)")
            return
        }
        #expect(await store.latest(limit: 10).count == 1)
    }

    /// A run with no scope is sent back for the missing fields and writes no artifact.
    ///
    /// This is the behaviour `OperatorSpec.defaultParameters` used to promise to avoid, by seeding a
    /// "concrete scope" for a run started without an explicit request. Every catalog entry left it
    /// empty, so it never did — and it could not have honestly, because the only thing it could seed
    /// for the watch is an address nobody named, which a governed run would then attest to in an
    /// artifact and a receipt. The field is gone; this pins what replaces it. `.needsRevision` rather
    /// than `.blocked` is the point: an incomplete request is correctable, and the instructions name
    /// the fields, so the caller learns what to supply instead of getting a report about a
    /// fabricated account.
    @Test
    func anUnscopedWatchRunIsSentBackForItsMissingFieldsRatherThanSeeded() async {
        let store = InMemoryArtifactStore()
        let pipeline = await makePipeline(store: store, judge: ObserveModeJudge(isObserveMode: true))
        let spec = OperatorCatalog.spec(for: OperatorCatalog.onChainWatchID)!

        let outcome = await pipeline.run(toolID: spec.tool.id, proposal: proposal(for: spec, parameters: [:]))

        guard case let .needsRevision(instructions) = outcome else {
            Issue.record("expected an unscoped watch to be sent back for revision, got \(outcome)")
            return
        }
        #expect(instructions.contains("chain"))
        #expect(instructions.contains("address"))
        #expect(await store.latest(limit: 10).isEmpty)
    }

    /// A read operator carrying **no** address and **no** chain still runs.
    ///
    /// The over-gating half of moving `address.format` and `chain.inScope` onto every operator, and
    /// the half nothing pinned. `OperatorCatalogContractTests.addressChainAndENSFieldsAreAlwaysChecked`
    /// asserts all four operators *require* the three checks, which is the under-gating half; a
    /// required check that refused a run with nothing to check would be just as much a defect, and it
    /// would be invisible to every test in this package that calls `OperatorExecutor.execute`
    /// directly — the executor does not run checks, the pipeline does.
    ///
    /// What makes this worth pinning rather than reading off `AddressFormatCheck` is that it is a
    /// property of three components agreeing: `OperatorRequest.toParameters()` must emit no `chain`,
    /// `address`, `ens` or `watchlist` key for an unscoped request; `CheckTargets.decode` must read
    /// that as *no targets* rather than one target full of `nil`s; and both checks must answer
    /// "nothing to check" with `passed: true`. A plain research brief is the shipping shape of this
    /// — `RuntimeHost.runResearchBrief(query:)` with no watchlist — and a block here would send it
    /// to `.needsRevision` or the Approval Inbox instead of producing the artifact and receipt that
    /// are the whole point of a read-only operator running in Observe.
    ///
    /// The checks registered here are the *real* `registerStandardChecks` ones, not stand-ins, which
    /// is what makes this an assertion about the catalog's required-check list.
    @Test(arguments: [
        (OperatorCatalog.researchBriefID, ["query": "gas usage"]),
        (OperatorCatalog.identityReviewID, ["identityID": "did:example:123"])
    ])
    func aReadOperatorWithNoAddressOrChainIsNotGatedByTheTargetShapedChecks(
        toolID: String,
        parameters: [String: String]
    ) async throws {
        let store = InMemoryArtifactStore()
        let pipeline = await makePipeline(store: store, judge: ObserveModeJudge(isObserveMode: true))
        let spec = try #require(OperatorCatalog.spec(for: toolID))
        // The premise: the request really does name no target, so the checks really do have nothing
        // to check. Asserted rather than assumed — if `toParameters()` ever started emitting a
        // placeholder chain or address, this test would otherwise keep passing for the wrong reason.
        #expect(parameters["chain"] == nil)
        #expect(parameters["address"] == nil)
        #expect(parameters["watchlist"] == nil)

        let outcome = await pipeline.run(
            toolID: spec.tool.id,
            proposal: proposal(for: spec, parameters: parameters)
        )

        guard case .executed = outcome else {
            Issue.record("\(toolID) with no address or chain was gated rather than run: \(outcome)")
            return
        }
        #expect(await store.latest(limit: 10).count == 1)
    }

    /// …and the same two checks still *bite* when the operator does carry a target.
    ///
    /// The other side of the test above, so "it ran" cannot be explained by the checks having been
    /// dropped rather than by them having nothing to check. A research brief declares no `address`
    /// field at all and its input schema is `allowsAdditionalFields: true`, so before these checks
    /// moved onto every operator this proposal cleared governance and rendered a malformed address
    /// into a durable artifact — and, through `LiveOnChainOperatorDataSource`, into an outbound RPC.
    ///
    /// Fails against the catalog that lists `address.format`/`chain.inScope` only on the two
    /// operators that declare those fields.
    @Test(arguments: [OperatorCatalog.researchBriefID, OperatorCatalog.identityReviewID])
    func aReadOperatorCarryingAMalformedAddressIsStillBlocked(toolID: String) async throws {
        let store = InMemoryArtifactStore()
        let pipeline = await makePipeline(store: store, judge: ObserveModeJudge(isObserveMode: true))
        let spec = try #require(OperatorCatalog.spec(for: toolID))
        let parameters = OperatorRequest(
            query: "gas usage",
            watchlist: [WatchTarget(chain: "ethereum", address: "0xnotanaddress")],
            identityID: "did:example:123"
        ).toParameters()

        let outcome = await pipeline.run(
            toolID: spec.tool.id,
            proposal: proposal(for: spec, parameters: parameters)
        )

        guard case let .blocked(reason) = outcome else {
            Issue.record("\(toolID) carrying a malformed address was not blocked: \(outcome)")
            return
        }
        #expect(reason.contains(StandardCheckID.addressFormat))
        #expect(await store.latest(limit: 10).isEmpty)
    }

    /// The high-risk prepared action is blocked under a read-only posture and escalated (never
    /// executed) when confirmation is permitted.
    @Test
    func preparedActionIsBlockedThenEscalatesForConfirmation() async {
        let store = InMemoryArtifactStore()
        let spec = OperatorCatalog.spec(for: OperatorCatalog.preparedActionID)!
        let params = OperatorRequest(
            watchlist: [WatchTarget(chain: "ethereum", address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045")]
        ).toParameters()

        let readOnly = await makePipeline(store: store, judge: ObserveModeJudge(isObserveMode: true))
        guard case .blocked = await readOnly.run(toolID: spec.tool.id, proposal: proposal(for: spec, parameters: params)) else {
            Issue.record("expected prepared action to be blocked under read-only posture")
            return
        }

        let confirming = await makePipeline(store: store, judge: ObserveModeJudge(isObserveMode: false))
        guard case .needsApproval = await confirming.run(toolID: spec.tool.id, proposal: proposal(for: spec, parameters: params)) else {
            Issue.record("expected prepared action to escalate for confirmation")
            return
        }
        // Nothing was executed in either case.
        #expect(await store.latest(limit: 10).isEmpty)
    }
}
