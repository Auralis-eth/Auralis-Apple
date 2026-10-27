/// Stable identifiers for the primary controls and states rendered by trusted UI.
///
/// These values are mirrored in AuraUI's central `A11yID` registry so app UI tests and
/// package-owned components share the same contract without coupling AuralisMissionControl to AuraUI.
public enum TrustedUIA11yID {
    public static let approvalSurface = "trustedui.approval.surface"
    public static let approvalApprove = "trustedui.approval.approve"
    public static let approvalDeny = "trustedui.approval.deny"
    public static let approvalDefer = "trustedui.approval.defer"
    public static let approvalSubmitted = "trustedui.approval.submitted"
    /// The block listing the parameters the action would actually execute against.
    public static let approvalParameters = "trustedui.approval.parameters"
    public static let draftEditor = "trustedui.draft.editor"
    public static let draftSave = "trustedui.draft.save"
    public static let permissionCard = "trustedui.permission.card"
    /// The lease row, which states whether the grant is live, revoked, expired, or not yet started.
    public static let permissionLease = "trustedui.permission.lease"
    public static let receiptCard = "trustedui.receipt.card"
    public static let contextBundleCard = "trustedui.contextbundle.card"
    /// The empty state shown when a bundle carries no fields.
    public static let contextBundleEmpty = "trustedui.contextbundle.empty"
    public static let riskBanner = "trustedui.risk.banner"
    public static let suggestionCard = "trustedui.suggestion.card"
    public static let suggestionAction = "trustedui.suggestion.action"
    public static let unavailable = "trustedui.unavailable"

    /// Every identifier declared above.
    ///
    /// The app-target mirror test can only compare the identifiers it names by hand, so an
    /// identifier added on one side of the AuraUI boundary and forgotten on the other stays green
    /// while the UI test that names it quietly matches nothing. Exposing the full set lets that
    /// test assert *completeness* rather than re-listing each constant.
    public static let all: [String] = [
        approvalSurface,
        approvalApprove,
        approvalDeny,
        approvalDefer,
        approvalSubmitted,
        approvalParameters,
        draftEditor,
        draftSave,
        permissionCard,
        permissionLease,
        receiptCard,
        contextBundleCard,
        contextBundleEmpty,
        riskBanner,
        suggestionCard,
        suggestionAction,
        unavailable
    ]
}
