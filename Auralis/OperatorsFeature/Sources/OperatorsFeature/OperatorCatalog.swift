import ArtifactCore
import AuralisRuntime

/// What kind of real work an operator performs — selects the data it gathers and how the artifact
/// body is composed. (P1-701..703)
public enum OperatorKind: String, Sendable, Equatable, Codable {
    case research
    case onChainWatch
    case identityReview
    case preparedAction
}

/// A bounded, first-class operator: a governed `ToolDefinition` paired with how it produces its
/// artifact. Body and telemetry are computed at run time from real inputs — not stored constants.
/// (P1-701..703)
public struct OperatorSpec: Sendable {
    public let tool: ToolDefinition
    public let kind: OperatorKind
    public let artifactType: ArtifactType
    /// Task kind used to resolve the inference/data route through `ModelRouting`.
    public let modelTaskKind: String
    /// Whether the run performs model inference (research/identity) or is a pure data read (watch).
    public let usesInference: Bool

    // There is deliberately no `defaultParameters` seed here. The field used to exist, documented as
    // the scope a run gets "when the operator is run without an explicit request … so a first run
    // still has a concrete scope", and every one of the four entries below left it empty — so its
    // readers always resolved `[:]` and the promise never held for any operator. It cannot be made to
    // hold honestly: the watch and the prepared action need a `chain` and an `address`, and a catalog
    // constant supplying either would be *fabricated* scope inside a governed, receipted run — an
    // artifact and a receipt attesting to an account nobody asked about. The seedless entry points
    // already fail cleanly, because the input schema requires those fields and `BeforeToolCallHook`
    // refuses the proposal that omits them. A refusal naming the missing input is the right answer.
    public init(
        tool: ToolDefinition,
        kind: OperatorKind,
        artifactType: ArtifactType,
        modelTaskKind: String,
        usesInference: Bool
    ) {
        self.tool = tool
        self.kind = kind
        self.artifactType = artifactType
        self.modelTaskKind = modelTaskKind
        self.usesInference = usesInference
    }

    /// Canonical static declaration for registry and Mission Control consumers.
    /// Live permissions, context, progress, and commitments intentionally do not appear here.
    public var manifest: OperatorManifest {
        OperatorManifest(
            id: tool.id,
            operatorVersion: "1.0.0",
            identity: .init(
                title: tool.title,
                purpose: "Run the \(tool.title) operator through the governed runtime.",
                intendedOutcomes: ["Produce a verified \(artifactType.rawValue) artifact"],
                principalScope: "requesting principal"
            ),
            context: .init(
                requiredFields: tool.inputSchema.fields.filter(\.isRequired).map(\.name),
                permittedMemoryScopes: nil,
                dataScopes: tool.inputSchema.fields.map(\.name),
                maximumAgeSeconds: nil
            ),
            reasoning: .init(
                supportsPlanning: false,
                workflowIDs: [modelTaskKind],
                decisionBoundaries: tool.impact.requiresConfirmation ? ["human confirmation required"] : [],
                usesInference: usesInference
            ),
            capabilities: .init(tool: tool, outputContracts: [artifactType.rawValue]),
            authority: .init(
                requestedPermissions: [tool.capability.rawValue],
                riskClassification: tool.impact.rawValue,
                confirmationBoundaries: tool.impact.requiresConfirmation ? ["before execution"] : [],
                revocationBehavior: "recheck before execution"
            ),
            execution: .init(
                supportedCommitmentTypes: [],
                lifecycleHooks: ["cancel"],
                cancellationBehavior: "cooperative",
                retryBehavior: "runtime governed",
                recoveryBehavior: "preserve receipt evidence"
            ),
            events: .init(
                subscribedCategories: [],
                triggerIDs: [],
                idempotencyRequirement: "correlation ID",
                schedulingRequirement: nil
            ),
            records: .init(
                artifactTypes: [artifactType.rawValue],
                requiresReceipt: tool.requiresReceipt,
                evidenceRequirements: tool.requiredCheckIDs
            ),
            outcomes: .init(
                successCriteria: ["artifact produced"],
                verificationRequirements: tool.requiredCheckIDs,
                failureSemantics: "report failure without claiming fulfillment",
                escalationSemantics: "follow declared impact and policy"
            ),
            interface: .init(
                representations: ["mission-control"],
                interventionSurfaces: tool.impact.requiresConfirmation ? ["approval-inbox"] : [],
                lifecycle: "registered",
                compatibility: "manifest-v1"
            )
        )
    }
}

/// The built-in operators. Impacts drive the crypto-scoped `DomainJudge`:
/// - Research Brief, On-Chain Watch (read), and Identity Review are non-crypto read-only → they run
///   even in Observe and produce artifacts + receipts.
/// - The On-Chain *prepared action* is crypto (`draftTransaction`, high-risk) → blocked in Observe,
///   escalated to the Approval Inbox in Assist, and only ever prepared (never autonomously executed).
public enum OperatorCatalog {
    public static let researchBriefID = "operator.research.brief"
    public static let onChainWatchID = "operator.onchain.watch"
    public static let identityReviewID = "operator.identity.review"
    public static let preparedActionID = "operator.onchain.prepareAction"

    /// Every operator writes an artifact *and* a receipt, so every operator validates both record
    /// shapes. Named once so a new operator can't be added without them (P0.5-802).
    ///
    /// The address, chain and ENS checks are in here rather than on the operators that *declare*
    /// those fields, because declaring a field and being able to receive one are different things.
    /// `ToolSchema.allowsAdditionalFields` defaults to `true` on these input schemas, and
    /// `OperatorRequest.toParameters()` emits `chain`, `address` and `ens` for any request carrying
    /// a watchlist — which `RuntimeHost.runResearchBrief(query:watchlist:)` accepts. So all four
    /// operators can receive all three, and only the two that declared them were checking.
    ///
    /// The ENS gap mattered most on `preparedAction`, the one surface a human reads before approving
    /// a `draftTransaction`: `WatchTarget.displayName` prefers the ENS name, so an unchallenged
    /// homoglyph (`vitalík.eth`) became the title of an approval.
    ///
    /// The address and chain gap is the same shape and was left behind when `ens.format` moved: a
    /// research brief or identity review could carry a watchlist whose address never passed
    /// `AddressFormatCheck` and whose chain was never tested against the policy's allowed set, then
    /// render that address into a durable artifact and — through `LiveOnChainOperatorDataSource` —
    /// name it in an outbound RPC. Both checks cost nothing where there is nothing to check; they
    /// return `passed: true` with "no address/chain to check".
    private static let recordShapeChecks = [
        StandardCheckID.contextFresh,
        StandardCheckID.addressFormat,
        StandardCheckID.chainInScope,
        StandardCheckID.ensNameFormat,
        RecordSchemaCheckID.artifactSchema,
        RecordSchemaCheckID.receiptSchema
    ]

    private static let artifactOutputSchema = ToolSchema(
        fields: [
            ToolSchemaField(name: "artifactID", kind: .uuid),
            ToolSchemaField(name: "modelProvider", kind: .string),
            ToolSchemaField(name: "modelClass", kind: .string),
            ToolSchemaField(name: "inferenceLocality", kind: .string),
            ToolSchemaField(name: "privacyImpact", kind: .string),
            ToolSchemaField(name: "promptTokens", kind: .number),
            ToolSchemaField(name: "completionTokens", kind: .number),
            ToolSchemaField(name: "tokensEstimated", kind: .bool),
            ToolSchemaField(name: "durationSeconds", kind: .number),
            ToolSchemaField(name: "estimatedCost", kind: .number),
            ToolSchemaField(name: "usesInference", kind: .bool),
            ToolSchemaField(name: "findingCount", kind: .number),
            ToolSchemaField(name: "alertCount", kind: .number),
            ToolSchemaField(name: "preparedActionCount", kind: .number),
            // *Which* target was prepared, not just how many. Optional, because most runs prepare
            // nothing and `.string`/`.address` reject an empty placeholder — they are omitted rather
            // than blanked.
            //
            // Without these the count was the only thing crossing the `ToolCallArtifact` boundary,
            // so the one consumer that escalates had to guess: `escalateFirstWatchFinding` drafted
            // against `operatorWatchlist.first` — UI state — while the composer had prepared the
            // action for whichever target actually had a failure. With a quiet account listed first
            // and an active one second, the Approval Inbox presented a high-risk prepared action for
            // an address the report found nothing for, and the artifact a human would consult to
            // check named a different one. An approval record and its evidence must not be able to
            // disagree about which account they are about.
            ToolSchemaField(name: "preparedActionChain", kind: .chain, isRequired: false),
            ToolSchemaField(name: "preparedActionAddress", kind: .address, isRequired: false),
            ToolSchemaField(name: "sourceReceiptCount", kind: .number)
        ],
        allowsAdditionalFields: false
    )

    public static let all: [OperatorSpec] = [
        OperatorSpec(
            tool: ToolDefinition(
                id: researchBriefID,
                title: "Research Brief",
                capability: .runPlugin,
                impact: .readOnly,
                inputSchema: ToolSchema(fields: [
                    ToolSchemaField(name: "query", kind: .string)
                ]),
                outputSchema: artifactOutputSchema,
                requiredCheckIDs: recordShapeChecks,
                requiresReceipt: true
            ),
            kind: .research,
            artifactType: .brief,
            modelTaskKind: ModelTaskKind.operatorResearchBrief,
            usesInference: true
        ),
        OperatorSpec(
            tool: ToolDefinition(
                id: onChainWatchID,
                title: "On-Chain Watch",
                capability: .runPlugin,
                impact: .readOnly,
                inputSchema: ToolSchema(fields: [
                    ToolSchemaField(name: "chain", kind: .chain),
                    ToolSchemaField(name: "address", kind: .address),
                    ToolSchemaField(name: "ens", kind: .string, isRequired: false)
                ]),
                outputSchema: artifactOutputSchema,
                // The address, chain and ENS checks all ride on `recordShapeChecks` for every
                // operator now — see the note there on why declaring a field and being able to
                // receive one are different questions. Listing them again here would be a second
                // place to forget.
                requiredCheckIDs: recordShapeChecks,
                requiresReceipt: true
            ),
            kind: .onChainWatch,
            artifactType: .report,
            modelTaskKind: ModelTaskKind.operatorOnChainWatch,
            usesInference: false
        ),
        OperatorSpec(
            tool: ToolDefinition(
                id: identityReviewID,
                title: "Identity Review",
                capability: .runPlugin,
                impact: .readOnly,
                inputSchema: ToolSchema(fields: [
                    ToolSchemaField(name: "identityID", kind: .string)
                ]),
                outputSchema: artifactOutputSchema,
                requiredCheckIDs: recordShapeChecks,
                requiresReceipt: true
            ),
            kind: .identityReview,
            artifactType: .report,
            modelTaskKind: ModelTaskKind.operatorIdentityReview,
            usesInference: true
        ),
        OperatorSpec(
            tool: ToolDefinition(
                id: preparedActionID,
                title: "Prepare On-Chain Action",
                capability: .draftTransaction,
                impact: .highRisk,
                inputSchema: ToolSchema(fields: [
                    ToolSchemaField(name: "chain", kind: .chain),
                    ToolSchemaField(name: "address", kind: .address)
                ]),
                outputSchema: artifactOutputSchema,
                requiredCheckIDs: recordShapeChecks,
                requiresReceipt: true
            ),
            kind: .preparedAction,
            artifactType: .planChecklist,
            modelTaskKind: ModelTaskKind.operatorPreparedAction,
            usesInference: true
        )
    ]

    public static func spec(for toolID: String) -> OperatorSpec? {
        all.first { $0.tool.id == toolID }
    }
}
