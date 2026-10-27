import AuralisPrimaryModels
import AuralisFoundation
import Foundation
import PolicyCore
import RuntimeCore

/// The governed-pipeline tools that back the app's `PolicyControlledAction`s, so wallet/plugin actions
/// flow through the *same* `GovernedToolPipeline` as everything else (one governed path — #3).
public enum PolicyActionCatalog {
    public static func toolID(for action: PolicyControlledAction) -> String {
        "policy.\(action.rawValue)"
    }

    public static let tools: [ToolDefinition] = [
        ToolDefinition(
            id: toolID(for: .signMessage),
            title: PolicyControlledAction.signMessage.title,
            capability: PolicyControlledAction.signMessage.capabilityID,
            impact: CapabilityImpactMapping.defaultImpact(for: PolicyControlledAction.signMessage.capabilityID),
            inputSchema: strictInputSchema([
                field("payload.kind", .string, allowedValue: PolicyControlledAction.signMessage.rawValue),
                field("payload.text", .string),
                field("payload.address", .address),
                field("payload.chainID", .chainID, isRequired: false)
            ]),
            outputSchema: strictSchema([
                field("signature", .signature),
                field("address", .address)
            ]),
            requiredCheckIDs: [
                PolicyToolCheckID.payloadValid,
                PolicyToolCheckID.chainAllowed,
                PolicyToolCheckID.addressChecksum,
                StandardCheckID.contextFresh,
                RecordSchemaCheckID.receiptSchema
            ],
            requiresReceipt: true
        ),
        ToolDefinition(
            id: toolID(for: .approveSpending),
            title: PolicyControlledAction.approveSpending.title,
            capability: PolicyControlledAction.approveSpending.capabilityID,
            impact: CapabilityImpactMapping.defaultImpact(for: PolicyControlledAction.approveSpending.capabilityID),
            inputSchema: strictInputSchema([
                field("payload.kind", .string, allowedValue: PolicyControlledAction.approveSpending.rawValue),
                field("payload.token", .address),
                field("payload.spender", .address),
                field("payload.amount", .unsignedQuantity),
                field("payload.owner", .address),
                field("payload.chainID", .chainID)
            ]),
            outputSchema: strictSchema([
                field("transactionHash", .transactionHash),
                field("token", .address),
                field("spender", .address),
                field("amount", .unsignedQuantity)
            ]),
            requiredCheckIDs: [
                PolicyToolCheckID.payloadValid,
                PolicyToolCheckID.chainAllowed,
                PolicyToolCheckID.approvalBounded,
                PolicyToolCheckID.addressChecksum,
                StandardCheckID.contextFresh,
                RecordSchemaCheckID.receiptSchema
            ],
            requiresReceipt: true
        ),
        ToolDefinition(
            id: toolID(for: .draftTransaction),
            title: PolicyControlledAction.draftTransaction.title,
            capability: PolicyControlledAction.draftTransaction.capabilityID,
            impact: CapabilityImpactMapping.defaultImpact(for: PolicyControlledAction.draftTransaction.capabilityID),
            inputSchema: strictInputSchema([
                field("payload.kind", .string, allowedValue: PolicyControlledAction.draftTransaction.rawValue),
                field("payload.from", .address),
                field("payload.to", .address, isRequired: false),
                field("payload.value", .unsignedQuantity),
                field("payload.data", .hexData),
                field("payload.chainID", .chainID)
            ]),
            outputSchema: strictSchema([
                field("transactionHash", .transactionHash),
                field("from", .address)
            ]),
            requiredCheckIDs: [
                PolicyToolCheckID.payloadValid,
                PolicyToolCheckID.chainAllowed,
                PolicyToolCheckID.addressChecksum,
                StandardCheckID.contextFresh,
                RecordSchemaCheckID.receiptSchema
            ],
            requiresReceipt: true
        ),
        ToolDefinition(
            id: toolID(for: .runPlugin),
            title: PolicyControlledAction.runPlugin.title,
            capability: PolicyControlledAction.runPlugin.capabilityID,
            impact: CapabilityImpactMapping.defaultImpact(for: PolicyControlledAction.runPlugin.capabilityID),
            inputSchema: strictInputSchema(
                [
                    field("payload.kind", .string, allowedValue: PolicyControlledAction.runPlugin.rawValue),
                    field("payload.pluginID", .string)
                ],
                allowedAdditionalFieldPrefixes: ["payload.plugin."]
            ),
            outputSchema: strictSchema([
                field("artifactID", .uuid),
                field("summary", .string)
            ]),
            // The only policy tool that produces an artifact, so it is the only one that also has an
            // artifact shape to validate.
            requiredCheckIDs: [
                PolicyToolCheckID.payloadValid,
                StandardCheckID.contextFresh,
                RecordSchemaCheckID.receiptSchema,
                RecordSchemaCheckID.artifactSchema
            ],
            requiresReceipt: true
        )
    ]

    private static func field(
        _ name: String,
        _ kind: ToolSchemaField.Kind,
        isRequired: Bool = true,
        allowedValue: String? = nil
    ) -> ToolSchemaField {
        ToolSchemaField(
            name: name,
            kind: kind,
            isRequired: isRequired,
            allowedValues: allowedValue.map { [$0] } ?? []
        )
    }

    /// The record-shape versions the host stamps onto every proposal, declared so a strict schema
    /// admits them.
    ///
    /// Optional rather than required: these are governance metadata the runtime supplies, and a
    /// proposal that predates the stamp is a revisable *policy* question for `receipt.schema` to
    /// answer, not an input-schema violation to bounce with field-level instructions.
    private static let recordSchemaFields = [
        field(RecordSchemaKey.artifactVersion, .number, isRequired: false),
        field(RecordSchemaKey.artifactType, .string, isRequired: false),
        field(StandardCheckParameterKey.contextRefreshedAt, .number, isRequired: false),
        field(StandardCheckParameterKey.freshnessEvaluatedAt, .number, isRequired: false)
    ]

    /// A strict *input* schema: the declared payload fields plus the runtime's record-shape stamp.
    private static func strictInputSchema(
        _ fields: [ToolSchemaField],
        allowedAdditionalFieldPrefixes: [String] = []
    ) -> ToolSchema {
        ToolSchema(
            fields: fields + recordSchemaFields,
            allowsAdditionalFields: false,
            allowedAdditionalFieldPrefixes: allowedAdditionalFieldPrefixes
        )
    }

    /// A strict *output* schema. Outputs carry no record-shape stamp — the runtime writes the record,
    /// the tool doesn't report one.
    private static func strictSchema(_ fields: [ToolSchemaField]) -> ToolSchema {
        ToolSchema(fields: fields, allowsAdditionalFields: false)
    }
}

/// The fail-closed default executor for policy-action tools, used by any `RuntimeHost` that has not been
/// given a real one.
///
/// A bare `RuntimeHost` has no wallet, signer, or plugin host, so it cannot perform the concrete effect
/// of a cleared `PolicyControlledAction`. Rather than fabricate a success artifact — which would let a
/// misconfigured host report a signature or transaction that never happened — it throws, so the pipeline
/// records a `.failed` outcome and receipt. The shipping app injects a real executor
/// (`WalletActionExecutor`); tests and previews that never clear a policy action keep this safe default.
public struct UnconfiguredPolicyActionExecutor: ToolExecuting {
    struct NotConfigured: LocalizedError {
        let toolID: String
        var errorDescription: String? {
            "No executor is configured to perform “\(toolID)”. Inject a policyActionExecutor (e.g. WalletActionExecutor) before clearing policy actions."
        }
    }

    public init() { }

    public func execute(
        _ tool: ToolDefinition,
        proposal: ActionProposal,
        authorization: ToolExecutionAuthorization
    ) async throws -> ToolCallArtifact {
        throw NotConfigured(toolID: tool.id)
    }
}

/// A `PolicyActionGating` conformer that runs each action through the governed pipeline and maps the
/// outcome back to the `PolicyGateResult` existing call sites expect. This is the app adapter for
/// the package-level `PolicyActionGateService` contract, but with one unified governance path
/// (judge + checks + receipts + events).
@MainActor
public struct PipelineBackedPolicyGate: PolicyActionGating {
    private let host: RuntimeHost

    public init(host: RuntimeHost) {
        self.host = host
    }

    /// Answers the *class-level* permission question ``PolicyActionGating`` defines this overload as:
    /// "would standing policy permit this kind of action right now?" — with no concrete operation and
    /// no effect.
    ///
    /// It deliberately does **not** forward to ``attempt(_:payload:actor:)`` with a `nil`
    /// payload, which is what it used to do. Every tool in ``PolicyActionCatalog`` declares a strict
    /// input schema requiring `payload.kind` and its operand fields, so a payload-free proposal was
    /// rejected by the pipeline's input-schema stage before policy was ever consulted. The verdict was
    /// therefore always `.needsRevision`, in every crypto mode, for every action — and the mapping
    /// below surfaced its field-level instructions ("missing required field “payload.kind”…") as
    /// `userMessage`, which `ProfileDetailView` shows verbatim in a "Policy decision" alert. A person
    /// asking what policy says about signing was told to revise a request they never composed.
    ///
    /// Evaluating standing policy directly is not a relaxation, and cannot become one: every
    /// ``PolicyControlledAction`` maps to a `.highRisk` or `.externalImpact` capability, and both
    /// return `true` from ``ActionImpactClass/requiresConfirmation``, so
    /// ``StandingToolPolicy/evaluate(action:mode:isCryptoCapability:requiresConfirmation:intent:)``
    /// cannot reach its `.allow` branch for any of them. The class-level answer is always a refusal or
    /// an approval requirement — which is why this is safe to answer without the pipeline, and why
    /// callers that read `isAllowed` as authorization (``AutopilotAuthorizer``) keep exactly the
    /// fail-closed behaviour they had.
    ///
    /// Nothing is executed, no approval is registered, and no receipt is written: a posture question
    /// is not an attempt, and minting an Approval Inbox entry for a payload-free proposal would create
    /// an approval that could only ever bounce on resume. The concrete path
    /// (``attempt(_:payload:actor:)``) remains the only way to actually run an action, with its
    /// deterministic checks, chain scope, address checksums, leases, and receipts all intact.
    public func attempt(
        _ action: PolicyControlledAction,
        actor: ActorRef
    ) async -> PolicyGateResult {
        // Bootstrap first so a governance-integrity failure is already reflected in `isPaused`;
        // `failClosed(violations:)` pauses the runtime, and this read is how that reaches the caller.
        // Memoised, so this costs nothing after the first call.
        await host.bootstrap()
        // The kill switch outranks standing policy. A paused runtime permits nothing, so reporting
        // "approval required" while the gate is closed would describe a route that does not exist.
        if host.isPaused {
            return PolicyGateResult(
                isAllowed: false,
                userMessage: host.pauseReason ?? "Operator activity is paused."
            )
        }
        let capability = action.capabilityID
        let verdict = StandingToolPolicy.evaluate(
            action: action,
            mode: host.cryptoMode,
            isCryptoCapability: CapabilityDomain.isCrypto(capability),
            requiresConfirmation: CapabilityImpactMapping.defaultImpact(for: capability).requiresConfirmation,
            // The action's own title, so the approval prompt reads as the thing a person recognises
            // ("Sign Message") rather than a raw policy identifier.
            intent: action.title
        )
        switch verdict {
        case .allow:
            // Unreachable for today's catalog (see the note above). Reported as permitted *in class*
            // with the concrete path named, so if a future lower-impact action does reach here the
            // caller is not told this was an authorization to act.
            return PolicyGateResult(
                isAllowed: true,
                userMessage: "Standing policy permits “\(action.title)”. Checks and receipts still apply when it runs."
            )
        case let .block(reason):
            return PolicyGateResult(isAllowed: false, userMessage: reason)
        case let .requireApproval(prompt):
            return PolicyGateResult(isAllowed: false, userMessage: prompt)
        }
    }

    /// Runs a concrete policy action through the governed pipeline — the only overload that can
    /// actually execute one. `payload` carries the operation's operands; a `nil` payload cannot
    /// satisfy the strict input schemas in ``PolicyActionCatalog`` and will be sent back as
    /// `.needsRevision`, which is why the class-level question has its own implementation above
    /// rather than routing through here.
    public func attempt(
        _ action: PolicyControlledAction,
        payload: PolicyActionPayload?,
        actor: ActorRef
    ) async -> PolicyGateResult {
        await host.bootstrap()
        let outcome = await host.runPolicyAction(
            action,
            actor: actor,
            payload: payload
        )
        switch outcome {
        case let .executed(artifact):
            return PolicyGateResult(isAllowed: true, userMessage: "", outputs: artifact.outputFields)
        case let .blocked(reason):
            return PolicyGateResult(isAllowed: false, userMessage: reason)
        case let .needsApproval(request):
            return PolicyGateResult(isAllowed: false, userMessage: request.prompt)
        case let .needsRevision(instructions):
            return PolicyGateResult(isAllowed: false, userMessage: instructions)
        case let .failed(reason):
            return PolicyGateResult(isAllowed: false, userMessage: reason)
        case let .evidenceIncomplete(_, failures):
            return PolicyGateResult(isAllowed: false, userMessage: failures.joined(separator: "; "))
        }
    }
}
