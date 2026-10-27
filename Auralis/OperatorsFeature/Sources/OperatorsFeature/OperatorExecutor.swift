import ArtifactCore
import Foundation
@_spi(ToolRegistration) import AuralisRuntime

/// The `ToolExecuting` behind the built-in operators. When the governed pipeline clears an operator it
/// gathers real local inputs through the ``OperatorDataSource``, composes a structured artifact from
/// them, and returns a linkable result. Only invoked for proposals the judge allows, so a blocked
/// crypto action never reaches here. (P1-701..703)
public struct OperatorExecutor: ToolExecuting {
    private let artifactStore: any ArtifactStore
    private let dataSource: any OperatorDataSource
    private let modelRouter: any ModelRouting
    private let modelInferenceClient: any ModelInferring
    private let now: @Sendable () -> Date

    public init(
        artifactStore: any ArtifactStore,
        dataSource: any OperatorDataSource = EmptyOperatorDataSource(),
        modelRouter: any ModelRouting = TaskKindModelRouter.localFirstDefault,
        modelInferenceClient: any ModelInferring = UnsupportedModelInferenceClient(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.artifactStore = artifactStore
        self.dataSource = dataSource
        self.modelRouter = modelRouter
        self.modelInferenceClient = modelInferenceClient
        self.now = now
    }

    /// Why a run could not produce an artifact.
    ///
    /// Plain `Error`, not `LocalizedError`. It used to conform and carry two hand-written sentences
    /// that nothing could ever read: the only consumer is `GovernedToolPipeline.execute`'s catch,
    /// which records `String(describing: error)`, so what actually reaches the receipt, the worklog,
    /// and the Approval Inbox is the case description — `artifactSchemaViolation(toolID: "…",
    /// problems: ["…"])`. The tests only assert `#expect(throws: ExecutionError.self)`, so nothing
    /// noticed. Routing the pipeline through `errorDescription` instead would change the recorded
    /// failure text for *every* tool in the repo, which is a receipt-content change and not one to
    /// make from inside this file — so the dead conformance is removed rather than given a reader,
    /// and the case descriptions are left to do the work they were already doing.
    enum ExecutionError: Error {
        /// No operator spec is registered for this tool id, so its result cannot be composed.
        case unknownOperator(String)
        /// The composed artifact violates `ArtifactSchema` — title or content bounds.
        case artifactSchemaViolation(toolID: String, problems: [String])
    }

    public func execute(
        _ tool: ToolDefinition,
        proposal: ActionProposal,
        authorization: ToolExecutionAuthorization
    ) async throws -> ToolCallArtifact {
        // Fail closed: a registered tool with no catalog spec cannot produce a real artifact, so throw
        // rather than fabricate a "Ran …" success the pipeline would emit as a receipt.
        guard let spec = OperatorCatalog.spec(for: tool.id) else {
            throw ExecutionError.unknownOperator(tool.id)
        }

        let request = OperatorRequest(parameters: proposal.parameters)
        let route = await modelRouter.route(forTaskKind: spec.modelTaskKind) ?? DefaultModelRoutes.localLanguageModel
        let started = now()
        // The prepared-action packet describes intent only; it reads no ledger and moves no funds.
        // The prepared-action packet describes intent only; it reads no ledger and moves no funds.
        //
        // Pinned by `aPreparedActionPacketNeverReadsTheLedger`, because this branch is invisible in
        // the composed output — `composePreparedAction(request:now:)` takes no `activity` argument, so
        // deleting the exemption changes no field, count or receipt link and the suite stayed green.
        // It is load-bearing all the same: `LiveOnChainOperatorDataSource.recentActivity` branches on
        // `request.watchlist` and never on the operator kind, so without this every prepared packet
        // would issue a live JSON-RPC read per watchlist entry naming the user's address.
        let activity = spec.kind == .preparedAction
            ? []
            : await dataSource.recentActivity(matching: request, limit: 50)
        var composed = OperatorArtifactComposer.compose(
            kind: spec.kind,
            request: request,
            activity: activity,
            now: started
        )
        var telemetry: InferenceTelemetry
        // Whether the *content below* was written by a model, which is a different question from
        // whether a model was called. `InferenceTelemetry.usesInference` answers the second — it is
        // the run's privacy-relevant fact, and it stays true the moment a prompt leaves the device.
        // `ArtifactProvenance.inference` answers the first, and this file already draws exactly that
        // line (see the note where it is stamped). The blank-response fallback below is the one path
        // where the two answers differ: a model ran, and produced none of this artifact.
        var bodyIsModelAuthored = false

        if spec.usesInference && route.locality == .remote {
            // Held in a local rather than built inline, because `inference.prompt` is the text that
            // actually left the device and is therefore the only honest basis for a token estimate
            // when the provider reports none. See `OperatorArtifactComposer.reportedTokenCounts`.
            let inference = try Self.inferenceRequest(
                taskKind: spec.modelTaskKind,
                request: request,
                activity: activity,
                fallbackBody: composed.body,
                // The *injected* clock, not `Date()`. This is the only place in the executor
                // that read the wall clock directly, in a package whose composer is documented
                // as "pure and deterministic, so … the artifact is reproducible from its
                // receipt". `started` keeps the context bundle on the same timeline as the
                // artifact's "Generated" stamp and the run's duration measurement, which is the
                // timeline a receipt is replayed against.
                gatheredAt: started,
                // **Two clock reads, not one.** This is the half moving off `Date()` did not
                // fix. `ContextBundleContract.validate` computes each field's age as
                // `validationDate - lastRefreshed`, so passing one value for both — whatever its
                // source — makes every age exactly `0` and the `maxAge: 60` requirements below
                // satisfied *by construction*: a declared governance requirement that cannot
                // fail is not a requirement. Reading the clock again here is what gives the
                // window something to measure. What it measures is the gap between `started` and
                // the moment the prompt is authorized, and that gap is not nominal — the
                // `await dataSource.recentActivity` above is `LiveOnChainOperatorDataSource` in
                // the shipping app, one bounded JSON-RPC call per watchlist entry. A gather that
                // takes longer than the window means the snapshot about to be sent to a remote
                // provider is already stale, and `missingFieldBehavior: .fail` refuses it rather
                // than sending it — the fail-closed direction, surfaced as a failed run with a
                // receipt naming the stale field.
                validatedAt: now()
            )
            let response = try await modelInferenceClient.respond(to: inference, using: route)
            // A blank response does not get to erase the report.
            //
            // The provider's prose replaces the composed body *wholesale*, and nothing downstream
            // refuses an empty one: `ArtifactSchema.problems(title:content:)` bounds the content
            // from above and requires only the *title* to be non-blank, so a provider returning
            // `""` (or whitespace) persisted a durable, receipted artifact with no body at all —
            // while its own `findingCount`, `alertCount` and linked receipts went on asserting what
            // the run found. The deterministic draft is already composed and was already handed to
            // the model as `operator.fallbackDraft`; falling back to it is what that field is for.
            //
            // Falling back is not free, though, and the cost is recorded rather than hidden: the
            // body below is then the deterministic composer's, so the artifact must not go on to
            // claim the provider wrote it. See `bodyIsModelAuthored` at the provenance stamp.
            //
            // "Blank" is judged with the same flattener the rest of this package renders untrusted
            // text through, not with `trimmingCharacters(in: .whitespacesAndNewlines)`. That set is
            // whitespace only: a response of `"\u{200B}"`, `"\u{FEFF}"` or a run of NULs is not
            // whitespace, so it was taken as authored content and persisted as a durable, receipted
            // artifact whose rendered body is *empty* — exactly the record this fallback exists to
            // prevent, spelled with invisibles instead of spaces. Worse than the space spelling, in
            // fact: the empty body was then credited to the provider through
            // `ArtifactProvenance.inference`, because `bodyIsModelAuthored` was true. The same scope
            // sanitizer the composer uses collapses `Cc`/`Cf` and every breaking scalar, so this
            // asks the one question that matters — is there anything a reader would see?
            bodyIsModelAuthored = !WatchTarget.flattenedText(response.content).isEmpty
            let providerBody = bodyIsModelAuthored ? response.content : composed.body
            composed = ComposedOperatorArtifact(
                title: composed.title,
                // The provider writes the prose; it does not get to drop the governance statement.
                // Everything else on this record already stays with the deterministic composer for
                // the same reason — the counts, and the prepared actions themselves, are facts about
                // the run rather than text about it, so a model can neither invent nor suppress one.
                // The body was the exception: on a remote route it was replaced wholesale, which on
                // the `.preparedAction` operator (`usesInference: true`, `draftTransaction`,
                // `.highRisk`) meant the artifact for an action that must not have happened yet
                // could read however the provider wrote it. See `enforcingConfirmFirst`.
                // Two separate restorations, because the provider can drop two different things.
                // `enforcingConfirmFirst` restores the claim about *authority* — that nothing was
                // signed. `enforcingPreparedTarget` restores the claim about *subject* — which
                // account the packet is for. The deterministic `## Target` block was the only thing
                // naming it, and it is dropped with the rest of the composed body on a remote
                // route, so a body that correctly said nothing was broadcast could still name an
                // address the run never prepared. `preparedActionAddress` crosses the
                // `ToolCallArtifact` boundary from the composer and is what
                // `MissionControlHomeModel.runOperator` escalates on, so the prose a human reads
                // and the draft they approve would be about different accounts.
                //
                // Both restorations *lead* the body rather than trailing it, because the provider
                // owns every line of what follows and a Markdown block only ever consumes lines
                // after the one that opens it — see `markdownSafePrefixing`. Confirm-first is
                // applied outermost, so the authority statement is the first thing rendered and the
                // `## Prepared target` block sits between it and the provider's prose.
                body: OperatorArtifactComposer.enforcingConfirmFirst(
                    OperatorArtifactComposer.enforcingPreparedTarget(
                        providerBody,
                        preparedActions: composed.preparedActions
                    ),
                    kind: spec.kind,
                    preparedActions: composed.preparedActions
                ),
                findingCount: composed.findingCount,
                alertCount: composed.alertCount,
                preparedActions: composed.preparedActions,
                attributedSourceReceiptIDs: composed.attributedSourceReceiptIDs
            )
            // The *route this executor resolved*, never the one the response claims.
            //
            // `response.telemetry` was taken wholesale, which meant the provider authored its own
            // locality, provider name, model class, privacy impact, cost, and `usesInference` flag —
            // and those are then stamped straight onto the artifact's provenance block and the
            // receipt's privacy-impact row. A provider registered for a *remote* route that returned
            // `route: .localLanguageModel` would send the prompt off-device — and this prompt carries
            // the full watchlist JSON: addresses, ENS names, labels — while both trust surfaces
            // reported "Apple Foundation Models / on-device". That is the same "two trust surfaces
            // disagreeing about one run" the provenance comment below was written to close, on the
            // side it did not cover.
            //
            // The split is what the executor can honestly observe versus what only the provider
            // knows: we resolved the route and we measured the wall clock, so those are ours; token
            // counts are the provider's to report. `usesInference: true` unconditionally, because we
            // are in the branch where we called a model — that is our observation, not its claim.
            //
            // The reported half is *checked* rather than believed — it was copied straight through,
            // including into `estimatedCost`, and `InferenceTelemetry`'s counts are non-optional
            // `Int`s that a provider fully controls. A zero against a non-empty prompt recorded a
            // paid remote hop as free, a negative count credited the session's cost ledger, and
            // `Int.max` traps `AgentSession.note(telemetry:)`'s `+=`. See
            // `OperatorArtifactComposer.reportedTokenCounts`, which falls back to the same
            // `EstimatedTokenCounter` the local branch uses and labels the result as an estimate.
            //
            // Unreachable today: `ModelProviderComposition` registers no remote provider, so
            // `RoutingInferenceClient` falls through to `UnsupportedModelInferenceClient`. It becomes
            // live with the first remote provider, which is the documented Phase 2 extension point —
            // i.e. exactly when nobody will be re-reading this function.
            telemetry = OperatorArtifactComposer.telemetry(
                route: route,
                reported: response.telemetry,
                // The prompt that actually left the device, and the text that actually came back.
                promptText: inference.prompt,
                completionText: response.content,
                duration: max(0, now().timeIntervalSince(started))
            )
        } else {
            let duration = max(0, now().timeIntervalSince(started))
            telemetry = OperatorArtifactComposer.telemetry(
                route: route,
                // This branch is reached precisely when no model was called — either the operator is
                // a pure data read, or it permits inference but the resolved route is local and the
                // body came from the deterministic composer above. Passing `spec.usesInference` here
                // reported estimated tokens and `usesInference: true` for the latter, which is a
                // claim about a model hop that never happened on the shipping local-first route.
                didInvokeModel: false,
                request: request,
                activity: activity,
                body: composed.body,
                duration: duration
            )
        }

        // Enforce the artifact field contract on the composed values, not on what the proposal
        // declared. The proposal declares neither title nor body, and on the inference path above the
        // body is a remote model response of unbounded length — so without this the schema's
        // `maximumContentLength` never actually gates anything and an over-limit artifact reaches
        // storage. Throwing here surfaces as a failed run with a receipt rather than a bad record.
        let schemaProblems = ArtifactSchema.problems(title: composed.title, content: composed.body)
        guard schemaProblems.isEmpty else {
            throw ExecutionError.artifactSchemaViolation(toolID: tool.id, problems: schemaProblems)
        }

        let artifact = try await artifactStore.create(
            ArtifactDraft(
                type: spec.artifactType,
                title: composed.title,
                creatorPlaybookID: request.playbookID,
                creatorOperatorID: tool.id,
                provenance: ArtifactProvenance(
                    actor: proposal.actor,
                    // Stamped only when a model actually ran, for the same reason
                    // `InferenceTelemetry.usesInference` exists — and this is the surface that was
                    // still missing it. `ArtifactProvenance.inference` is optional precisely so an
                    // artifact can say "no model produced this", but it was populated from
                    // `route.provenance` unconditionally, and `InferenceProvenance` carries no
                    // "didn't actually run" flag. Mission Control gates its artifact
                    // Inference/Provider/Model class/Privacy impact block, and the artifact export
                    // lines, on `inference != nil` alone — so a deterministically composed body
                    // (every run on the shipping local-first route, which is three of the four
                    // catalog operators plus the pure-read watch) presented as the work of
                    // "Apple Foundation Models / local-language-model", while the same run's receipt
                    // telemetry said `usesInference: false`. Two trust surfaces disagreeing about one
                    // run. The route is still recorded on the receipt's output fields for
                    // provenance; what is dropped here is only the claim that it inferred anything.
                    //
                    // Gated on `bodyIsModelAuthored` rather than `telemetry.usesInference`, because
                    // those stopped being the same question when the blank-response fallback landed.
                    // A provider that returns `""` is still a model hop — the prompt, watchlist JSON
                    // and all, did leave the device — so `usesInference` stays true and the receipt
                    // keeps reporting the remote locality and its privacy impact. But the body that
                    // reaches this draft is then the deterministic composer's, and stamping
                    // `route.provenance` on it told Mission Control's artifact Inference/Provider/
                    // Model class block, the export lines, and `comparisonRows`' provenance row that
                    // a third-party model authored text it never saw. That is the same overclaim
                    // this very field was made optional to prevent, arriving through the other door.
                    inference: bodyIsModelAuthored ? telemetry.route.provenance : nil
                ),
                // What the composition attributed, not everything the data source handed over. These
                // links and the `sourceReceiptCount` below are the two halves of one record's claim
                // about its evidence, and the body and `findingCount` are the other half — linking
                // the raw feed made them contradict each other on the one kind that narrows its
                // input. The subset is the composer's, deliberately: it owns the `(chain, address)`
                // rule, and a second copy here would be the same defect in a new place.
                relatedReceiptIDs: composed.attributedSourceReceiptIDs,
                content: composed.body
            )
        )

        // The prepared target travels with the count, so a consumer escalating on
        // `preparedActionCount > 0` can draft against the account the report actually prepared
        // rather than inferring one from its own UI state. Omitted entirely when nothing was
        // prepared: the schema fields are optional and reject an empty string.
        var preparedTarget: [String: String] = [:]
        if let first = composed.preparedActions.first {
            preparedTarget["preparedActionChain"] = first.chain
            preparedTarget["preparedActionAddress"] = first.address
        }

        return ToolCallArtifact(
            id: artifact.id,
            toolID: tool.id,
            summary: composed.title,
            outputFields: .flatMerged([
                ["artifactID": artifact.id.uuidString],
                telemetry.outputFields,
                [
                    "findingCount": "\(composed.findingCount)",
                    "alertCount": "\(composed.alertCount)",
                    "preparedActionCount": "\(composed.preparedActions.count)",
                    "sourceReceiptCount": "\(artifact.relatedReceiptIDs.count)"
                ],
                preparedTarget
            ])
        )
    }

    private static func inferenceRequest(
        taskKind: String,
        request: OperatorRequest,
        activity: [ObservedActivity],
        fallbackBody: String,
        gatheredAt: Date,
        validatedAt: Date
    ) throws -> ModelInferenceRequest {
        let activityText = activity.map { "- \($0.title): \($0.detail)" }.joined(separator: "\n")
        let parameterSummary = request.toParameters()
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
        // When the inputs below were gathered — deliberately the *earlier* of the two stamps the
        // caller supplies, which is the conservative direction: the activity feed is fetched after
        // `started`, so dating it from `started` can only ever over-state its age, never under-state
        // it. Separate from `validatedAt`; see the note at the call site for why collapsing the two
        // made the freshness window unfalsifiable.
        let contextNow = gatheredAt
        return try ModelInferenceRequest.authorizing(
            taskKind: taskKind,
            instructions: [
                "Produce the operator artifact body for Auralis Mission Control.",
                "Stay grounded in the supplied local activity and request parameters.",
                "Do not claim that a wallet action was executed."
            ],
            bundle: ContextBundle(fields: [
                ContextField(key: "operator.request.query", stringValue: request.query ?? "No query supplied", dataClass: .userProvided, source: .userProvided, lastRefreshed: contextNow),
                ContextField(key: "operator.request.parameters", stringValue: parameterSummary, dataClass: .derived, source: .operatorExecutor, lastRefreshed: contextNow),
                ContextField(key: "operator.localActivity", stringValue: activityText.isEmpty ? "No matching local activity." : activityText, dataClass: .derived, source: .operatorExecutor, lastRefreshed: contextNow),
                ContextField(key: "operator.fallbackDraft", stringValue: fallbackBody, dataClass: .derived, source: .operatorExecutor, lastRefreshed: contextNow)
            ]),
            contract: ContextBundleContract(
                identifier: "model.\(taskKind)",
                requirements: [
                    ContextFieldRequirement(key: "operator.request.query", allowedDataClasses: [.userProvided], maxAge: 60, authoritativeSource: .userProvided, missingFieldBehavior: .fail),
                    ContextFieldRequirement(key: "operator.request.parameters", allowedDataClasses: [.derived], maxAge: 60, authoritativeSource: .operatorExecutor, missingFieldBehavior: .fail),
                    ContextFieldRequirement(key: "operator.localActivity", allowedDataClasses: [.derived], maxAge: 60, authoritativeSource: .operatorExecutor, missingFieldBehavior: .fail),
                    ContextFieldRequirement(key: "operator.fallbackDraft", allowedDataClasses: [.derived], maxAge: 60, authoritativeSource: .operatorExecutor, missingFieldBehavior: .fail)
                ]
            ),
            validationDate: validatedAt
        ) { context in
            return """
            Query: \(context.field("operator.request.query")?.stringValue ?? "")
            Activity:
            \(context.field("operator.localActivity")?.stringValue ?? "")

            Local deterministic draft:
            \(context.field("operator.fallbackDraft")?.stringValue ?? "")
            """
        }
    }
}

private extension Dictionary where Key == String, Value == String {
    static func flatMerged(_ dictionaries: [Dictionary]) -> Dictionary {
        dictionaries.reduce(into: [:]) { partial, dictionary in
            partial.merge(dictionary) { _, new in new }
        }
    }
}

@_spi(ToolRegistration) public extension ToolRegistry {
    /// Registers all built-in operators so the runtime can resolve them by id.
    @discardableResult
    func registerOperators() async -> [ToolDefinition] {
        var conflicts: [ToolDefinition] = []
        for spec in OperatorCatalog.all where !register(spec.tool).succeeded {
            conflicts.append(spec.tool)
        }
        return conflicts
    }
}
