import ReceiptsCore

public enum ExternalLinkOpenProvenance: String, Equatable, Sendable {
    case userConfirmedTap = "user_confirmed_tap"
    case operatorConfirmed = "operator_confirmed"
    case pluginConfirmed = "plugin_confirmed"

    public var receiptActor: ReceiptActor {
        switch self {
        case .userConfirmedTap:
            return .user
        case .operatorConfirmed, .pluginConfirmed:
            return .system
        }
    }

    /// The structured "who acted" leg of actor attribution (P0.5-602).
    ///
    /// Each case maps to the `ActorKind` that matches its initiator — an operator pack is
    /// `"operator"` and a plugin is `"plugin"`, not a background workflow. This is the column
    /// receipt history filters and groups on, so collapsing both onto `.workflow` would make an
    /// operator-initiated navigation indistinguishable from a sync job in the trust surface. These
    /// receipts are persisted, so a mislabel is not correctable after the fact.
    ///
    /// Stays consistent with ``receiptActor`` by construction: `ReceiptActorDetail.coarseActor`
    /// treats only `"human"` as a user, and only ``userConfirmedTap`` maps to `.human` here.
    public var receiptActorDetail: ReceiptActorDetail {
        switch self {
        case .userConfirmedTap:
            return .human
        case .operatorConfirmed:
            return .operatorPack("external_link")
        case .pluginConfirmed:
            return .plugin("external_link")
        }
    }

    /// The "under what authority" leg of actor attribution (P0.5-601).
    ///
    /// Only a user-confirmed tap is human approval. An operator or plugin opens a link under the
    /// standing external-link allowlist with no person in the loop, so recording `humanApproval`
    /// for those cases would have a receipt assert an approval nobody gave.
    ///
    /// Built through the canonical factories rather than by spelling `source` by hand, so a rename
    /// of the underlying `AuthorityRef.Source` wire value reaches this call site instead of leaving
    /// it writing a stale string that still compiles. `capability` stays nil deliberately: no
    /// `CapabilityID` covers external navigation, and inventing one here would persist an id that
    /// resolves to nothing.
    public var receiptAuthorityDetail: ReceiptAuthorityDetail {
        switch self {
        case .userConfirmedTap:
            return .humanApproval(reason: "The person explicitly opened the external link.")
        case .operatorConfirmed:
            return .policyDefault(reason: "An operator opened a link on the external-link allowlist.")
        case .pluginConfirmed:
            return .policyDefault(reason: "A plugin opened a link on the external-link allowlist.")
        }
    }
}
