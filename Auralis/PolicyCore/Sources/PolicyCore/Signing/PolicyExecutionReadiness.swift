/// Validates future high-risk execution requirements before any signing-capable
/// flow is allowed to construct an executable operation.
public enum PolicyExecutionReadiness {
    public static func evaluate(
        action: PolicyControlledAction,
        evidence: PolicyExecutionEvidence,
        signingChainAllowlist: SigningChainAllowlist = .denyAll
    ) -> PolicyGateResult {
        let requirements = action.futureExecutionControls

        if requirements.contains(.signingAccess), !evidence.signingAccessAvailable {
            return denied("Signing-capable account access is required")
        }

        if requirements.contains(.capabilityGrant),
           evidence.capabilityGrant?.capabilityID != action.capabilityID.rawValue {
            return denied("Capability grant is required")
        }

        if requirements.contains(.requesterProvenance), evidence.requesterProvenance == nil {
            return denied("Requester provenance is required")
        }

        if requirements.contains(.userConfirmation), evidence.userConfirmation == nil {
            return denied("User confirmation is required")
        }

        if requirements.contains(.approvedReceipt), evidence.approvedReceiptID == nil {
            return denied("Approved policy receipt is required")
        }

        if action == .draftTransaction {
            guard let preview = evidence.draftTransactionPreview else {
                return denied("Transaction preview is required")
            }

            guard signingChainAllowlist.contains(preview.targetChain) else {
                return denied("Target chain is not allowed for signing")
            }
        }

        return PolicyGateResult(isAllowed: true, userMessage: "")
    }

    private static func denied(_ message: String) -> PolicyGateResult {
        PolicyGateResult(isAllowed: false, userMessage: message)
    }
}

public extension PolicyControlledAction {
    var futureExecutionControls: Set<PolicyExecutionControl> {
        switch self {
        case .signMessage:
            return [
                .signingAccess,
                .capabilityGrant,
                .requesterProvenance,
                .userConfirmation,
                .approvedReceipt,
            ]
        case .approveSpending:
            return [
                .signingAccess,
                .capabilityGrant,
                .requesterProvenance,
                .userConfirmation,
                .approvedReceipt,
            ]
        case .draftTransaction:
            return [
                .signingAccess,
                .capabilityGrant,
                .requesterProvenance,
                .userConfirmation,
                .approvedReceipt,
                .chainAllowlist,
                .transactionPreview,
            ]
        case .runPlugin:
            return [
                .capabilityGrant,
                .requesterProvenance,
                .userConfirmation,
                .approvedReceipt,
            ]
        }
    }
}
