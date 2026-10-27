public enum PolicyExecutionControl: String, CaseIterable, Sendable {
    case signingAccess
    case capabilityGrant
    case requesterProvenance
    case userConfirmation
    case approvedReceipt
    case chainAllowlist
    case transactionPreview
}
