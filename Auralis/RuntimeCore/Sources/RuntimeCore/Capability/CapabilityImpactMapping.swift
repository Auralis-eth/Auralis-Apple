import AuralisFoundation

/// Maps a canonical ``CapabilityID`` to the ``ActionImpactClass`` of *executing* it.
///
/// This is the impact-class analogue of `CapabilityActionMapping` (which maps to policy actions):
/// it lets any layer derive "how risky is this capability" without a bespoke switch each time. Wallet
/// capabilities are high-risk; exports and plugin runs reach outside; music mutations are reversible
/// local writes; playback is read-only.
public enum CapabilityImpactMapping {
    public static func defaultImpact(for capability: CapabilityID) -> ActionImpactClass {
        switch capability {
        case .signMessage, .approveSpending, .draftTransaction:
            return .highRisk
        case .runPlugin, .musicExport:
            return .externalImpact
        case .playlistManagement,
             .autoOrganization,
             .musicLibraryClassification,
             .metadataOverride,
             .backgroundMusicTask,
             .playbackQueue:
            return .reversibleWrite
        case .audioPlayback:
            return .readOnly
        }
    }

    /// The *least* impact any step on `capability` can have — the floor below which a caller's claim
    /// about a step cannot sink it.
    ///
    /// Distinct from ``defaultImpact(for:)``, which is the impact of *executing* the capability.
    /// Applying the execute-impact to a non-execute step overstates it: a plugin run that only
    /// inspects local state reaches outside nothing, and `OperatorCatalog` really does declare the
    /// Research Brief tool `.readOnly` while `runPlugin` as a whole is `.externalImpact`. Applying
    /// *no* floor understates it, which is the defect ``PlanStepProposal`` carried: a plan step
    /// naming `sign_message` and declaring itself `observe` proposed `.readOnly`, and in Operate
    /// mode `StandingToolPolicy` cleared it with no confirmation because `.readOnly` does not
    /// require one.
    ///
    /// The line between the two is whether the capability *has* a read-only mode at all:
    ///
    /// - Wallet capabilities do not. There is no way to sign a message, approve spending, or draft
    ///   a transaction that only reads — so a step naming one is high-risk however it labels itself.
    /// - `musicExport` does not. Producing an export always puts data somewhere else; inspecting
    ///   what *would* be exported is `musicLibraryClassification`, a different capability.
    /// - Everything else does. A plugin run, a library classification, or a queue inspection can
    ///   genuinely only look, so those keep whatever the step claims and are governed by their
    ///   `.execute` rung (and, on the legacy path, by `AutopilotAuthorizer`'s gate call).
    public static func minimumImpact(for capability: CapabilityID) -> ActionImpactClass {
        switch capability {
        case .signMessage, .approveSpending, .draftTransaction:
            return .highRisk
        case .musicExport:
            return .externalImpact
        case .runPlugin,
             .playlistManagement,
             .autoOrganization,
             .musicLibraryClassification,
             .metadataOverride,
             .backgroundMusicTask,
             .playbackQueue,
             .audioPlayback:
            return .readOnly
        }
    }
}
