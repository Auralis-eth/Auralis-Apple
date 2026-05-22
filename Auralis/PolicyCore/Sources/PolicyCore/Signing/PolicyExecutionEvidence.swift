import AuralisPrimaryModels

/// Evidence required before a future high-risk action can become executable.
public struct PolicyExecutionEvidence: Equatable, Sendable {
    public let signingAccessAvailable: Bool
    public let capabilityGrant: PolicyCapabilityGrant?
    public let requesterProvenance: PolicyRequesterProvenance?
    public let userConfirmation: PolicyUserConfirmation?
    public let approvedReceiptID: String?
    public let draftTransactionPreview: DraftTransactionPreviewEvidence?

    public init(
        signingAccessAvailable: Bool = false,
        capabilityGrant: PolicyCapabilityGrant? = nil,
        requesterProvenance: PolicyRequesterProvenance? = nil,
        userConfirmation: PolicyUserConfirmation? = nil,
        approvedReceiptID: String? = nil,
        draftTransactionPreview: DraftTransactionPreviewEvidence? = nil
    ) {
        self.signingAccessAvailable = signingAccessAvailable
        self.capabilityGrant = capabilityGrant
        self.requesterProvenance = requesterProvenance
        self.userConfirmation = userConfirmation
        self.approvedReceiptID = approvedReceiptID
        self.draftTransactionPreview = draftTransactionPreview
    }

    public static let none = PolicyExecutionEvidence()
}

public struct PolicyCapabilityGrant: Equatable, Sendable {
    public let capabilityID: String

    public init(capabilityID: String) {
        self.capabilityID = capabilityID
    }
}

public struct PolicyRequesterProvenance: Equatable, Sendable {
    public let requesterID: String
    public let displayName: String

    public init(requesterID: String, displayName: String) {
        self.requesterID = requesterID
        self.displayName = displayName
    }
}

public struct PolicyUserConfirmation: Equatable, Sendable {
    public let confirmedSummary: String
    public let confirmationReceiptID: String

    public init(confirmedSummary: String, confirmationReceiptID: String) {
        self.confirmedSummary = confirmedSummary
        self.confirmationReceiptID = confirmationReceiptID
    }
}

public struct DraftTransactionPreviewEvidence: Equatable, Sendable {
    public let targetChain: Chain
    public let gasEstimate: String
    public let contractInfo: String
    public let verifiedDestination: String
    public let simulationSummary: String

    public init(
        targetChain: Chain,
        gasEstimate: String,
        contractInfo: String,
        verifiedDestination: String,
        simulationSummary: String
    ) {
        self.targetChain = targetChain
        self.gasEstimate = gasEstimate
        self.contractInfo = contractInfo
        self.verifiedDestination = verifiedDestination
        self.simulationSummary = simulationSummary
    }
}
