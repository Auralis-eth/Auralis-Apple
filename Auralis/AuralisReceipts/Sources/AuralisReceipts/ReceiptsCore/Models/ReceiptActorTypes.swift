import Foundation

public enum ReceiptActor: String, Codable, Equatable, Sendable {
    case user
    case system
}

/// Structured attribution persisted alongside the coarse ``ReceiptActor`` (P0.5-602 "first-class actor
/// column"). Where `ReceiptActor` only says *user vs system*, this records *which* non-human actor acted
/// (operator/plugin/workflow/routine/model), under what identity, and — for model actors — with what
/// inference provenance. AuralisReceipts owns this persisted representation and the AuralisRuntime bridge.
///
/// Fields are stored as raw strings rather than the richer `AuralisRuntime` enums (`ActorKind`,
/// `InferenceLocality`) so the persisted schema stays stable; the typed bridge lives beside this
/// receipt model. All fields are optional so the type round-trips cleanly for
/// legacy receipts that predate the structured column.
public struct ReceiptActorDetail: Codable, Equatable, Sendable {
    /// Raw `ActorKind` value ("human", "operator", "plugin", "workflow", "scheduledRoutine", "model").
    public let kind: String
    /// Stable identifier for non-human actors (plugin id, workflow id, routine id, model id).
    public let identifier: String?
    public let displayName: String?
    /// Raw `InferenceLocality` value ("local"/"remote"), present only for model-backed actors.
    public let inferenceLocality: String?
    public let inferenceProvider: String?
    public let inferenceModelClass: String?

    public init(
        kind: String,
        identifier: String? = nil,
        displayName: String? = nil,
        inferenceLocality: String? = nil,
        inferenceProvider: String? = nil,
        inferenceModelClass: String? = nil
    ) {
        self.kind = kind
        self.identifier = identifier
        self.displayName = displayName
        self.inferenceLocality = inferenceLocality
        self.inferenceProvider = inferenceProvider
        self.inferenceModelClass = inferenceModelClass
    }

    /// The coarse ``ReceiptActor`` this attribution collapses to, for the filter column that predates
    /// the structured one. The leaf-side inverse of `AuralisRuntime.ActorRef.receiptActor`, and kept
    /// consistent with it: only `"human"` is a user, every other kind is the system.
    ///
    /// Exists so callers that only hold a `ReceiptActorDetail` cannot drift the two columns apart by
    /// hardcoding one of them.
    public var coarseActor: ReceiptActor {
        kind == "human" ? .user : .system
    }
}

/// Canonical constructors, so the ~30 receipt-writing call sites across the app don't each spell a
/// raw `ActorKind` string by hand (P0.5-602).
///
/// Packages that can see `AuralisRuntime` should prefer `ActorRef.…receiptActorDetail` — the typed path.
/// These exist for the leaves that deliberately cannot (`MusicFeature`, `NFTKit`, `AuralisReceipts`
/// itself), where the alternative is a bare string literal per site.
public extension ReceiptActorDetail {
    /// The person using the app.
    static let human = ReceiptActorDetail(kind: "human")

    /// Internal, non-user-initiated work with no more specific identity. Mirrors
    /// `AuralisRuntime.ActorRef.system`, including its `"system"` identifier, so the two agree.
    static let system = ReceiptActorDetail(kind: "workflow", identifier: "system")

    /// A named background workflow — a sync job, an indexer, a cache refresh. Preferred over
    /// ``system`` whenever the caller knows which workflow it is, which is nearly always.
    static func workflow(_ identifier: String, displayName: String? = nil) -> ReceiptActorDetail {
        ReceiptActorDetail(kind: "workflow", identifier: identifier, displayName: displayName)
    }

    /// An operator pack. `"operator"` is the wire value of `ActorKind.operatorAgent`.
    static func operatorPack(_ identifier: String, displayName: String? = nil) -> ReceiptActorDetail {
        ReceiptActorDetail(kind: "operator", identifier: identifier, displayName: displayName)
    }

    static func plugin(_ identifier: String, displayName: String? = nil) -> ReceiptActorDetail {
        ReceiptActorDetail(kind: "plugin", identifier: identifier, displayName: displayName)
    }

    static func scheduledRoutine(_ identifier: String, displayName: String? = nil) -> ReceiptActorDetail {
        ReceiptActorDetail(kind: "scheduledRoutine", identifier: identifier, displayName: displayName)
    }

    /// A model actor with inference provenance. `locality` takes `InferenceLocality`'s raw values
    /// (`"local"`/`"remote"`); callers that hold a typed `ModelRoute` should use the `AuralisRuntime`
    /// bridge instead of this.
    static func model(
        _ identifier: String,
        locality: String? = nil,
        provider: String? = nil,
        modelClass: String? = nil
    ) -> ReceiptActorDetail {
        ReceiptActorDetail(
            kind: "model",
            identifier: identifier,
            inferenceLocality: locality,
            inferenceProvider: provider,
            inferenceModelClass: modelClass
        )
    }
}

/// The authority a receipt's action proceeded under — the "under what authority" leg of actor
/// attribution (P0.5-601/602), stored alongside ``ReceiptActorDetail``'s "who acted".
///
/// A capability check answers whether an actor may act; this records *which grant* said yes, so a
/// receipt can be audited after the fact rather than only asserting that something was allowed.
/// Fields are raw strings so the receipt representation remains a versionable persisted wire model;
/// the typed `AuralisRuntime.AuthorityRef` bridge lives beside this type.
public struct ReceiptAuthorityDetail: Codable, Equatable, Sendable {
    /// Raw `AuthorityRef.Source` value ("lease", "humanApproval", "policyDefault").
    public let source: String
    /// The authorizing capability lease's id, present when `source == "lease"`.
    public let leaseID: String?
    /// Raw `CapabilityID` the authority covers.
    public let capability: String?
    /// Raw `CapabilityLeaseScope` value the grant was scoped to.
    public let scope: String?
    /// The operator-facing reason recorded on the grant.
    public let reason: String?
    /// When the authorizing grant expires, so history shows how time-boxed the permission was.
    public let expiresAt: Date?

    public init(
        source: String,
        leaseID: String? = nil,
        capability: String? = nil,
        scope: String? = nil,
        reason: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.source = source
        self.leaseID = leaseID
        self.capability = capability
        self.scope = scope
        self.reason = reason
        self.expiresAt = expiresAt
    }

    /// Standing app policy permitted the action; no capability lease was involved.
    ///
    /// The honest authority for the large body of routine, read-only, and user-initiated work that
    /// never consults the lease registry — indexing a library, refreshing holdings, resolving an ENS
    /// name. Recording it is what lets a receipt answer "what let this happen?" instead of persisting
    /// a null column. Work that *does* resolve a grant records `source: "lease"` instead.
    public static func policyDefault(capability: String? = nil, reason: String? = nil) -> ReceiptAuthorityDetail {
        ReceiptAuthorityDetail(source: "policyDefault", capability: capability, reason: reason)
    }

    /// A person approved this action directly, so their decision is the authority.
    public static func humanApproval(capability: String? = nil, reason: String? = nil) -> ReceiptAuthorityDetail {
        ReceiptAuthorityDetail(source: "humanApproval", capability: capability, reason: reason)
    }
}
