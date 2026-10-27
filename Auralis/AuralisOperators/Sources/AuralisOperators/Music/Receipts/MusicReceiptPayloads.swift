import AuralisCrypto
import AuralisFoundation
import Foundation
import AuralisReceipts

public enum MusicReceiptActorValue: String, Sendable {
    case user
    case system
    case `operator`
    case plugin

    // There is deliberately no `receiptActor` here. The coarse column is derived from the detail
    // actually written (`ReceiptActorDetail.coarseActor`, see `MusicReceiptEventLogger.append`); a
    // second, independent `actor → ReceiptActor` switch could drift out of agreement with it about
    // whether a human acted, and that disagreement would be sealed inside the chain hash.

    /// Full-fidelity attribution for the structured receipt column (P0.5-602).
    ///
    /// This enum is a coarse *kind* — it carries no identity — so this is only the fallback used
    /// when a caller supplies no `MusicReceiptContext.actorDetail`. Raw `ActorKind` values match
    /// `AuralisRuntime.ActorRef` (`"operator"` is the wire value for its `operatorAgent` case), so a
    /// Music receipt can at least say *which* non-human actor acted.
    var actorDetail: ReceiptActorDetail {
        switch self {
        // Built from the canonical constructors rather than raw `kind:` strings — that is what they
        // exist for, and a typo'd kind here would silently disagree with `coarseActor`.
        case .user:
            return .human
        case .system:
            return .workflow("music")
        // Feature-scoped identifiers rather than bare kinds: an identifier-less detail resolves to
        // the identity key `operator#anonymous`, which every anonymous operator in the app shares —
        // so a lease or denial aimed at one would apply to all of them. These in-tree identifiers are
        // the most precise honest answer *this enum* can give; a caller that knows the real pack id
        // must pass it as `MusicReceiptContext.actorDetail`, which `MusicReceiptEventLogger` prefers
        // over this derivation.
        case .operator:
            return .operatorPack("music.operator")
        case .plugin:
            return .plugin("music.plugin")
        }
    }
}

public enum MusicReceiptTriggerCause: String, Sendable {
    case userInitiated = "user_initiated"
    case systemSync = "system_sync"
    case operatorAction = "operator_action"
    case pluginAction = "plugin_action"
    case autoAdvance = "auto_advance"
    case dryRun = "dry_run"
    case policyDenied = "policy_denied"

    var provenance: String {
        switch self {
        case .userInitiated:
            return "user_provided"
        case .systemSync, .dryRun, .autoAdvance:
            return "local_cache"
        case .operatorAction:
            return "operator"
        case .pluginAction:
            return "plugin"
        case .policyDenied:
            return "policy"
        }
    }
}

public enum MusicReceiptPolicyDecision: String, Sendable {
    case allowed
    case blocked
    case dryRun = "dry_run"
}

public enum MusicReceiptRollbackAvailability: String, Sendable {
    case none
    case deletePlaylist = "delete_playlist"
    case manualReverseChange = "manual_reverse_change"
}

public struct MusicReceiptContext: Sendable {
    public let triggerCause: MusicReceiptTriggerCause
    public let actor: MusicReceiptActorValue
    /// The caller's own attribution, preferred over the kind-derived ``MusicReceiptActorValue/actorDetail``.
    public let actorDetail: ReceiptActorDetail?
    public let accountAddress: String?
    public let chain: Chain?
    public let correlationID: String?
    public let surface: String?

    /// - Parameter actor: Who acted. Deliberately has **no default** (P0.5-602): defaulting to
    ///   `.user` would let a new background call site silently record that a *human* performed work
    ///   the app did on its own — the one misattribution that is worse than none, since it is the
    ///   `.user` value the trust surfaces treat as consent.
    /// - Parameter actorDetail: The acting identity, when the caller knows it — e.g.
    ///   `ActorRef.receiptActorDetail` from a package that can see `AuralisRuntime`, which this leaf
    ///   cannot. `actor` is only a *kind*, so without this every operator pack invoking a music tool
    ///   would be recorded as the in-tree `music.operator`: a lease, denial or rate limit keyed on
    ///   that identity would then bind the wrong principal, and the audit chain would name the wrong
    ///   pack. Optional rather than required because the existing in-app call sites genuinely have
    ///   no identity to offer, and the derived fallback is the honest answer for them.
    public init(
        triggerCause: MusicReceiptTriggerCause,
        actor: MusicReceiptActorValue,
        actorDetail: ReceiptActorDetail? = nil,
        accountAddress: String? = nil,
        chain: Chain? = nil,
        correlationID: String? = nil,
        surface: String? = nil
    ) {
        self.triggerCause = triggerCause
        self.actor = actor
        self.actorDetail = actorDetail
        self.accountAddress = accountAddress
        self.chain = chain
        self.correlationID = correlationID
        self.surface = surface
    }
}

// `MusicPolicyReceiptContext` was removed here; see the note in `MusicReceiptEventLogger` where its
// only consumer, `recordPolicyBlocked`, also lived.

public struct MusicReceiptStateSummary: Equatable, Sendable {
    public let values: [String: ReceiptJSONValue]

    public init(values: [String: ReceiptJSONValue]) {
        self.values = values
    }

    public static func playlist(
        playlistID: UUID,
        playlistTitle: String,
        itemCount: Int,
        changedFields: [String] = []
    ) -> MusicReceiptStateSummary {
        playlist(
            playlistID: playlistID.uuidString,
            playlistTitle: playlistTitle,
            itemCount: itemCount,
            changedFields: changedFields
        )
    }

    public static func playlist(
        playlistID: String,
        playlistTitle: String,
        itemCount: Int,
        changedFields: [String] = []
    ) -> MusicReceiptStateSummary {
        var values: [String: ReceiptJSONValue] = [
            "playlistID": .string(playlistID),
            "playlistTitle": .string(playlistTitle),
            "itemCount": .number(Double(itemCount))
        ]

        if !changedFields.isEmpty {
            values["changedFields"] = .array(changedFields.sorted().map(ReceiptJSONValue.string))
        }

        return MusicReceiptStateSummary(values: values)
    }

    public static func autoOrganization(candidateCount: Int, collectionCount: Int) -> MusicReceiptStateSummary {
        MusicReceiptStateSummary(
            values: [
                "candidateCount": .number(Double(candidateCount)),
                "collectionCount": .number(Double(collectionCount))
            ]
        )
    }

    public static func classification(
        totalCount: Int,
        playableCount: Int,
        metadataOnlyCount: Int,
        artworkCount: Int
    ) -> MusicReceiptStateSummary {
        MusicReceiptStateSummary(
            values: [
                "totalCount": .number(Double(totalCount)),
                "playableCount": .number(Double(playableCount)),
                "metadataOnlyCount": .number(Double(metadataOnlyCount)),
                "artworkCount": .number(Double(artworkCount))
            ]
        )
    }

    public static func task(
        name: String,
        inputCount: Int,
        outputCount: Int,
        removedCount: Int = 0
    ) -> MusicReceiptStateSummary {
        MusicReceiptStateSummary(
            values: [
                "taskName": .string(name),
                "inputCount": .number(Double(inputCount)),
                "outputCount": .number(Double(outputCount)),
                "removedCount": .number(Double(removedCount))
            ]
        )
    }

    public static func export(
        name: String,
        format: String,
        itemCount: Int
    ) -> MusicReceiptStateSummary {
        MusicReceiptStateSummary(
            values: [
                "exportName": .string(name),
                "format": .string(format),
                "itemCount": .number(Double(itemCount))
            ]
        )
    }
}

extension ReceiptPayloadField {
    static func object(
        _ key: String,
        values: [String: ReceiptJSONValue]
    ) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .object(values),
            sensitivity: .public,
            valueKind: .object
        )
    }

    static func nullableObject(
        _ key: String,
        summary: MusicReceiptStateSummary?
    ) -> ReceiptPayloadField {
        if let summary {
            return .object(key, values: summary.values)
        }

        return .null(key)
    }
}
