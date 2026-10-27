import AuralisCrypto
import Foundation
import AuralisOperators
import AuralisReceipts
import Testing

/// What an external-link receipt records about who opened the link and under what authority, and the
/// defaults an open request carries before a caller says otherwise.
struct ExternalLinkProvenanceTests {
    @Test("provenance maps to the actor kind of its initiator")
    func provenanceMapsToInitiatorActorKind() {
        #expect(ExternalLinkOpenProvenance.userConfirmedTap.receiptActorDetail.kind == "human")

        let operatorDetail = ExternalLinkOpenProvenance.operatorConfirmed.receiptActorDetail
        #expect(operatorDetail.kind == "operator")
        #expect(operatorDetail.identifier == "external_link")

        let pluginDetail = ExternalLinkOpenProvenance.pluginConfirmed.receiptActorDetail
        #expect(pluginDetail.kind == "plugin")
        #expect(pluginDetail.identifier == "external_link")
    }

    @Test("no provenance is attributed to an anonymous background workflow")
    func provenanceNeverAttributesToWorkflow() {
        // `.workflow(…)` files an open in receipt history alongside sync jobs and cache refreshes.
        // These receipts are persisted, so such a mislabel cannot be corrected after the fact.
        for provenance in [
            ExternalLinkOpenProvenance.userConfirmedTap,
            .operatorConfirmed,
            .pluginConfirmed
        ] {
            #expect(provenance.receiptActorDetail.kind != "workflow")
        }
    }

    @Test("coarse and structured actor attribution agree for every provenance")
    func provenanceActorLegsAgree() {
        for provenance in [
            ExternalLinkOpenProvenance.userConfirmedTap,
            .operatorConfirmed,
            .pluginConfirmed
        ] {
            #expect(provenance.receiptActorDetail.coarseActor == provenance.receiptActor)
        }
    }

    @Test("only a user-confirmed tap is recorded as human approval")
    func provenanceAuthorityReflectsWhoApproved() {
        #expect(ExternalLinkOpenProvenance.userConfirmedTap.receiptAuthorityDetail.source == "humanApproval")
        #expect(ExternalLinkOpenProvenance.operatorConfirmed.receiptAuthorityDetail.source == "policyDefault")
        #expect(ExternalLinkOpenProvenance.pluginConfirmed.receiptAuthorityDetail.source == "policyDefault")
    }

    @Test("every provenance records why it was authorized, and claims no capability")
    func provenanceAuthorityCarriesReasonAndNoCapability() {
        // The reason is the only human-readable account of why the app left for a web page, so an
        // empty one turns a trust receipt into a bare `policyDefault`. `capability` stays nil because
        // no `CapabilityID` covers external navigation, and an invented id would persist as a
        // reference that resolves to nothing.
        for provenance in [
            ExternalLinkOpenProvenance.userConfirmedTap,
            .operatorConfirmed,
            .pluginConfirmed
        ] {
            let authority = provenance.receiptAuthorityDetail
            #expect(authority.capability == nil, "\(provenance.rawValue) persisted a capability id that resolves to nothing.")
            #expect(authority.reason?.isEmpty == false, "\(provenance.rawValue) recorded no reason for the open.")
        }

        // Pinned, not just non-empty: an operator- or plugin-initiated open must not describe itself
        // as something a person did.
        #expect(
            ExternalLinkOpenProvenance.operatorConfirmed.receiptAuthorityDetail.reason ==
                "An operator opened a link on the external-link allowlist."
        )
        #expect(
            ExternalLinkOpenProvenance.pluginConfirmed.receiptAuthorityDetail.reason ==
                "A plugin opened a link on the external-link allowlist."
        )
        #expect(
            ExternalLinkOpenProvenance.userConfirmedTap.receiptAuthorityDetail.reason ==
                "The person explicitly opened the external link."
        )
    }

    @Test("provenance wire values are stable")
    func provenanceWireValuesAreStable() {
        // Persisted on every external-link receipt, so renaming a case would orphan history.
        #expect(ExternalLinkOpenProvenance.userConfirmedTap.rawValue == "user_confirmed_tap")
        #expect(ExternalLinkOpenProvenance.operatorConfirmed.rawValue == "operator_confirmed")
        #expect(ExternalLinkOpenProvenance.pluginConfirmed.rawValue == "plugin_confirmed")
    }

    @Test("audit requirement drives whether a missing receipt blocks the open")
    func auditRequirementGatesDurability() {
        #expect(ExternalLinkAuditRequirement.durable.requiresDurableAudit)
        #expect(ExternalLinkAuditRequirement.bestEffort.requiresDurableAudit == false)
    }

    @Test("an open request defaults to a user tap that requires a durable receipt")
    func openRequestDefaultsToDurableUserTap() throws {
        let url = try #require(URL(string: "https://etherscan.io/tx/0xabc"))
        let request = ExternalLinkOpenRequest(label: "Explorer", url: url, surface: "test")

        #expect(request.provenance == .userConfirmedTap)
        #expect(request.auditRequirement == .durable)
        #expect(request.requiresDurableAudit)
        #expect(request.accountAddress == nil)
        #expect(request.chain == nil)
    }
}
