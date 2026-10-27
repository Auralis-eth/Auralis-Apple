import Foundation
import RuntimeCore

public struct OperatorManifest: Identifiable, Equatable, Codable, Sendable {
    public static let currentVersion = 1

    public let manifestVersion: Int
    public let id: String
    public let operatorVersion: String
    public let identity: Identity
    public let context: ContextRequirements
    public let reasoning: Reasoning
    public let capabilities: Capabilities
    public let authority: Authority
    public let execution: Execution
    public let events: Events
    public let records: Records
    public let outcomes: Outcomes
    public let interface: Interface

    public init(
        manifestVersion: Int = OperatorManifest.currentVersion,
        id: String,
        operatorVersion: String,
        identity: Identity,
        context: ContextRequirements,
        reasoning: Reasoning,
        capabilities: Capabilities,
        authority: Authority,
        execution: Execution,
        events: Events,
        records: Records,
        outcomes: Outcomes,
        interface: Interface
    ) {
        self.manifestVersion = manifestVersion
        self.id = id
        self.operatorVersion = operatorVersion
        self.identity = identity
        self.context = context
        self.reasoning = reasoning
        self.capabilities = capabilities
        self.authority = authority
        self.execution = execution
        self.events = events
        self.records = records
        self.outcomes = outcomes
        self.interface = interface
    }

    public var definitionProblems: [String] {
        var problems: [String] = []
        if manifestVersion != Self.currentVersion { problems.append("unsupported manifest version") }
        if id.isEmpty { problems.append("operator ID must not be empty") }
        if operatorVersion.isEmpty { problems.append("operator version must not be empty") }
        if identity.title.isEmpty { problems.append("operator title must not be empty") }
        problems.append(contentsOf: capabilities.tool.definitionProblems)
        return problems
    }
}

public extension OperatorManifest {
    struct Identity: Equatable, Codable, Sendable {
        public let title: String
        public let purpose: String
        public let intendedOutcomes: [String]
        public let principalScope: String

        public init(title: String, purpose: String, intendedOutcomes: [String], principalScope: String) {
            self.title = title
            self.purpose = purpose
            self.intendedOutcomes = intendedOutcomes
            self.principalScope = principalScope
        }
    }

    struct ContextRequirements: Equatable, Codable, Sendable {
        public let requiredFields: [String]
        public let permittedMemoryScopes: [String]?
        public let dataScopes: [String]
        public let maximumAgeSeconds: Double?

        public init(requiredFields: [String], permittedMemoryScopes: [String]?, dataScopes: [String], maximumAgeSeconds: Double?) {
            self.requiredFields = requiredFields
            self.permittedMemoryScopes = permittedMemoryScopes
            self.dataScopes = dataScopes
            self.maximumAgeSeconds = maximumAgeSeconds
        }
    }

    struct Reasoning: Equatable, Codable, Sendable {
        public let supportsPlanning: Bool
        public let workflowIDs: [String]
        public let decisionBoundaries: [String]
        public let usesInference: Bool?

        public init(supportsPlanning: Bool, workflowIDs: [String], decisionBoundaries: [String], usesInference: Bool?) {
            self.supportsPlanning = supportsPlanning
            self.workflowIDs = workflowIDs
            self.decisionBoundaries = decisionBoundaries
            self.usesInference = usesInference
        }
    }

    struct Capabilities: Equatable, Codable, Sendable {
        public let tool: ToolDefinition
        public let outputContracts: [String]

        public init(tool: ToolDefinition, outputContracts: [String]) {
            self.tool = tool
            self.outputContracts = outputContracts
        }
    }

    struct Authority: Equatable, Codable, Sendable {
        public let requestedPermissions: [String]
        public let riskClassification: String
        public let confirmationBoundaries: [String]
        public let revocationBehavior: String

        public init(requestedPermissions: [String], riskClassification: String, confirmationBoundaries: [String], revocationBehavior: String) {
            self.requestedPermissions = requestedPermissions
            self.riskClassification = riskClassification
            self.confirmationBoundaries = confirmationBoundaries
            self.revocationBehavior = revocationBehavior
        }
    }

    struct Execution: Equatable, Codable, Sendable {
        public let supportedCommitmentTypes: [String]
        public let lifecycleHooks: [String]
        public let cancellationBehavior: String
        public let retryBehavior: String
        public let recoveryBehavior: String

        public init(supportedCommitmentTypes: [String], lifecycleHooks: [String], cancellationBehavior: String, retryBehavior: String, recoveryBehavior: String) {
            self.supportedCommitmentTypes = supportedCommitmentTypes
            self.lifecycleHooks = lifecycleHooks
            self.cancellationBehavior = cancellationBehavior
            self.retryBehavior = retryBehavior
            self.recoveryBehavior = recoveryBehavior
        }
    }

    struct Events: Equatable, Codable, Sendable {
        public let subscribedCategories: [String]
        public let triggerIDs: [String]
        public let idempotencyRequirement: String
        public let schedulingRequirement: String?

        public init(subscribedCategories: [String], triggerIDs: [String], idempotencyRequirement: String, schedulingRequirement: String?) {
            self.subscribedCategories = subscribedCategories
            self.triggerIDs = triggerIDs
            self.idempotencyRequirement = idempotencyRequirement
            self.schedulingRequirement = schedulingRequirement
        }
    }

    struct Records: Equatable, Codable, Sendable {
        public let artifactTypes: [String]
        public let requiresReceipt: Bool
        public let evidenceRequirements: [String]

        public init(artifactTypes: [String], requiresReceipt: Bool, evidenceRequirements: [String]) {
            self.artifactTypes = artifactTypes
            self.requiresReceipt = requiresReceipt
            self.evidenceRequirements = evidenceRequirements
        }
    }

    struct Outcomes: Equatable, Codable, Sendable {
        public let successCriteria: [String]
        public let verificationRequirements: [String]
        public let failureSemantics: String
        public let escalationSemantics: String

        public init(successCriteria: [String], verificationRequirements: [String], failureSemantics: String, escalationSemantics: String) {
            self.successCriteria = successCriteria
            self.verificationRequirements = verificationRequirements
            self.failureSemantics = failureSemantics
            self.escalationSemantics = escalationSemantics
        }
    }

    struct Interface: Equatable, Codable, Sendable {
        public let representations: [String]
        public let interventionSurfaces: [String]
        public let lifecycle: String
        public let compatibility: String

        public init(representations: [String], interventionSurfaces: [String], lifecycle: String, compatibility: String) {
            self.representations = representations
            self.interventionSurfaces = interventionSurfaces
            self.lifecycle = lifecycle
            self.compatibility = compatibility
        }
    }
}
