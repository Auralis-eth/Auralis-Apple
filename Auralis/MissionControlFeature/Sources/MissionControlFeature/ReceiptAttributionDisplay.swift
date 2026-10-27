import AuralisPrimaryModels
import AuralisFoundation
import Foundation
import ReceiptsCore
import RuntimeCore

/// Renders a receipt's stored attribution for trust surfaces (P0.5-601/602).
///
/// Receipts persist attribution as raw strings (`ReceiptActorDetail`/`ReceiptAuthorityDetail` live in
/// the dependency-free `AuralisPrimaryModels` leaf). This maps them back through the `RuntimeCore`
/// enums so the UI shows "Scheduled routine — Morning Brief" instead of the coarse "system", and
/// degrades to the coarse actor for receipts written before the structured columns existed.
enum ReceiptAttributionDisplay {
    /// Who acted, as a user-facing label. Falls back to the coarse `user`/`system` value when a
    /// receipt carries no structured detail.
    static func actorLabel(for receipt: ReceiptRecord) -> String {
        guard let detail = receipt.actorDetail else {
            return receipt.actor.rawValue.capitalized
        }
        let kindTitle = ActorKind(rawValue: detail.kind)?.displayTitle ?? detail.kind
        return label(kindTitle: kindTitle, name: detail.displayName ?? detail.identifier)
    }

    /// Who acted, for surfaces that hold a typed ``ActorRef`` rather than a stored receipt — worklog
    /// entries, execution records, sessions (P0.5-602). Shares the receipt overload's formatting so a
    /// worklog row and the receipt for the same action read identically.
    ///
    /// Delegates to `ActorRef.attributionLabel` so this and `TrustedUIKit`'s approval sheet cannot
    /// drift: the sheet used to drop the kind whenever the ref had a display name, which made the
    /// receipt better attributed than the decision it recorded.
    static func actorLabel(for actor: ActorRef) -> String {
        actor.attributionLabel
    }

    /// Where the model ran, for a typed model-backed actor. `nil` for non-model actors.
    static func inferenceLabel(for actor: ActorRef) -> String? {
        guard let inference = actor.inference else { return nil }
        guard let provider = inference.provider, !provider.isEmpty else {
            return inference.locality.privacyImpactShort
        }
        return "\(inference.locality.privacyImpactShort) · \(provider)"
    }

    /// Under what authority a typed entry proceeded. `nil` when the entry is pre-authority — a
    /// proposal recorded, or checks run, before any grant was consulted.
    static func authorityLabel(for authority: AuthorityRef?) -> String? {
        guard let authority else { return nil }
        switch authority.source {
        case .lease:
            guard let capability = authority.capability else { return "Capability lease" }
            return "Capability lease — \(CapabilityRegistry.descriptor(for: capability).title)"
        case .humanApproval:
            return "Approved by you"
        case .policyDefault:
            return "Allowed by standing policy"
        }
    }

    private static func label(kindTitle: String, name: String?) -> String {
        guard let name, !name.isEmpty else { return kindTitle }
        return "\(kindTitle) — \(name)"
    }

    /// Where the model ran, for model-backed actors. `nil` when no inference was recorded.
    static func inferenceLabel(for receipt: ReceiptRecord) -> String? {
        guard let detail = receipt.actorDetail,
              let rawLocality = detail.inferenceLocality,
              let locality = InferenceLocality(rawValue: rawLocality) else {
            return nil
        }
        guard let provider = detail.inferenceProvider, !provider.isEmpty else {
            return locality.privacyImpactShort
        }
        return "\(locality.privacyImpactShort) · \(provider)"
    }

    /// Under what authority the action proceeded. `nil` when none was recorded.
    static func authorityLabel(for receipt: ReceiptRecord) -> String? {
        guard let detail = receipt.authorityDetail else { return nil }
        switch AuthorityRef.Source(rawValue: detail.source) {
        case .lease:
            // `capability` persists as CapabilityID's snake_case wire value, so map it back to the
            // registry's human title rather than showing "sign_message" to a person.
            guard let raw = detail.capability, let capability = CapabilityID(rawValue: raw) else {
                return "Capability lease"
            }
            return "Capability lease — \(CapabilityRegistry.descriptor(for: capability).title)"
        case .humanApproval:
            return "Approved by you"
        case .policyDefault:
            return "Allowed by standing policy"
        case nil:
            return detail.source
        }
    }

    /// The operator-facing reason recorded on the authorizing grant, when there was one.
    static func authorityReason(for receipt: ReceiptRecord) -> String? {
        guard let reason = receipt.authorityDetail?.reason, !reason.isEmpty else { return nil }
        return reason
    }
}
