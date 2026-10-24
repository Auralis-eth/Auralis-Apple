import CapabilitiesCore
import Foundation
import RuntimeCore

public extension ActorRef {
    /// Collapses the rich actor model down to the two-case `ReceiptActor` the receipt store persists
    /// today. Only a human maps to `.user`; every non-human actor maps to `.system`.
    ///
    /// Retained for the coarse `user`/`system` filter and the pre-existing chain-hash field; the full
    /// attribution now travels in `receiptActorDetail` (P0.5-602).
    var receiptActor: ReceiptActor {
        switch kind {
        case .human:
            return .user
        case .operatorAgent, .plugin, .workflow, .scheduledRoutine, .model:
            return .system
        }
    }

    /// Full-fidelity attribution for the structured receipt column (P0.5-602): preserves *which*
    /// non-human actor acted and, for model actors, the inference provenance — none of which the
    /// two-case `receiptActor` can express.
    var receiptActorDetail: ReceiptActorDetail {
        ReceiptActorDetail(
            kind: kind.rawValue,
            identifier: identifier,
            displayName: displayName,
            inferenceLocality: inference?.locality.rawValue,
            inferenceProvider: inference?.provider,
            inferenceModelClass: inference?.modelClass
        )
    }
}

public extension ActorRef {
    /// Reconstructs a typed actor from the receipt-column form (P0.5-602).
    ///
    /// The inverse of ``receiptActorDetail`` for receipt readers that need typed runtime attribution.
    ///
    /// An unrecognized `kind` degrades to a namespaced `.workflow` ref rather than failing: this runs
    /// on the path that *records* attribution, so degrading to an honest "some unrecognized actor"
    /// beats refusing to write.
    ///
    /// The degrade goes through ``ActorRef/init(persistedKind:identifier:displayName:inference:)``,
    /// the same helper the JSON path uses, so the two read paths cannot drift.
    /// `ReceiptActorDetail.kind` is a free `String` read back out of SwiftData, and this ref reaches
    /// `grantingLease(to:)`/`firstDenial(for:to:)` — so passing an unknown kind's identifier through
    /// verbatim would let `{kind: "somethingNew", identifier: "planner.daily"}` resolve to
    /// `workflow#id:planner.daily` and inherit that workflow's lease.
    init(receiptActorDetail detail: ReceiptActorDetail) {
        // `.map`, not `.flatMap`: a *present but unrecognized* locality degrades to `.remote` with
        // provider and model class preserved, exactly as `InferenceProvenance.init(from:)` does on
        // the JSON path. Flat-mapping dropped the whole provenance instead, which both lost the
        // recorded provider and — for a model actor — left it with no provenance at all.
        let inference = detail.inferenceLocality.map { rawLocality in
            InferenceProvenance(
                locality: InferenceLocality(rawValue: rawLocality) ?? .remote,
                provider: detail.inferenceProvider,
                modelClass: detail.inferenceModelClass
            )
        }
        self.init(
            persistedKind: detail.kind,
            identifier: detail.identifier,
            displayName: detail.displayName,
            inference: inference
        )
    }
}

public extension AuthorityRef {
    /// Reconstructs a typed authority from the receipt-column form — the inverse of
    /// ``receiptAuthorityDetail``, so trust surfaces reading stored receipts can render
    /// ``displaySummary`` instead of re-deriving the copy from raw strings.
    ///
    /// Returns `nil` for an unrecognized `source`, because unlike an actor there is no safe degraded
    /// authority: inventing one would assert that *something* permitted the action when this build
    /// cannot tell what. Callers show no authority rather than a wrong one.
    init?(receiptAuthorityDetail detail: ReceiptAuthorityDetail) {
        guard let source = Source(rawValue: detail.source) else { return nil }
        self.init(
            source: source,
            leaseID: detail.leaseID.flatMap(UUID.init(uuidString:)),
            capability: detail.capability.flatMap(CapabilityID.init(rawValue:)),
            scope: detail.scope.flatMap(CapabilityLeaseScope.init(rawValue:)),
            reason: detail.reason,
            expiresAt: detail.expiresAt
        )
    }

    /// The receipt-column form of this authority (P0.5-601/602), so a stored receipt can answer
    /// "under what authority?" without re-deriving typed runtime state from raw strings.
    var receiptAuthorityDetail: ReceiptAuthorityDetail {
        ReceiptAuthorityDetail(
            source: source.rawValue,
            leaseID: leaseID?.uuidString,
            capability: capability?.rawValue,
            scope: scope?.rawValue,
            reason: reason,
            expiresAt: expiresAt
        )
    }
}
