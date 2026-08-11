import CapabilitiesCore
import PolicyCore

/// Maps a canonical ``CapabilityID`` to the ``PolicyControlledAction`` the app's policy
/// gate understands, so a plan step can be evaluated by the *existing* policy layer
/// rather than a parallel one.
///
/// Wallet capabilities map to their specific policy actions. Every other state-changing
/// capability (music organization, exports, plugins, playback mutations) maps to
/// ``PolicyControlledAction/runPlugin`` — the gate's catch-all for "tool/plugin executes
/// something", which is exactly what an agent step is. This keeps one gate as the single
/// source of truth for what is allowed.
public enum CapabilityActionMapping {
    public static func policyAction(for capability: CapabilityID) -> PolicyControlledAction {
        switch capability {
        case .signMessage:
            return .signMessage
        case .approveSpending:
            return .approveSpending
        case .draftTransaction:
            return .draftTransaction
        case .runPlugin,
             .playlistManagement,
             .autoOrganization,
             .musicLibraryClassification,
             .metadataOverride,
             .backgroundMusicTask,
             .musicExport,
             .playbackQueue,
             .audioPlayback:
            return .runPlugin
        }
    }
}
