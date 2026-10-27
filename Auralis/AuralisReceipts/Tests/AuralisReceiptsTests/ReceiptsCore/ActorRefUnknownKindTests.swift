import AuralisFoundation
import Foundation
@testable import AuralisReceipts
@testable import AuralisRuntime
import Testing

/// A future build adding a seventh `ActorKind` must not make this build delete history.
///
/// Every store that persists an `ActorRef` reads it back through `compactMap`/`try?`, so a throwing
/// decode does not surface as "unknown actor" — it silently drops the whole worklog entry, lease,
/// session, or execution record. These tests pin the degrade path and, just as importantly, that the
/// degraded ref cannot inherit authority it was never granted.
@Suite("ActorRef unknown kind tolerance")
struct ActorRefUnknownKindTests {
    private func decode(_ json: String) throws -> ActorRef {
        try JSONDecoder().decode(ActorRef.self, from: Data(json.utf8))
    }

    @Test("an unknown kind decodes instead of throwing")
    func unknownKindDecodes() throws {
        let actor = try decode(#"{"kind":"quantumOracle","identifier":"oracle.1"}"#)

        #expect(actor.kind == .workflow)
        #expect(actor.identifier == "unrecognized-kind:quantumOracle:oracle.1")
        #expect(actor.displayName == "Unrecognized actor (quantumOracle)")
    }

    @Test("an unknown kind with no identifier still decodes")
    func unknownKindWithoutIdentifierDecodes() throws {
        let actor = try decode(#"{"kind":"quantumOracle"}"#)

        #expect(actor.kind == .workflow)
        #expect(actor.identifier == "unrecognized-kind:quantumOracle")
    }

    @Test("a degraded actor cannot claim a real workflow's lease")
    func degradedActorDoesNotAliasARealWorkflow() async throws {
        // The whole point of namespacing the identifier: folding an unknown kind onto `.workflow`
        // must not let it match a grant made to an actual workflow of the same id.
        let degraded = try decode(#"{"kind":"quantumOracle","identifier":"planner.daily"}"#)
        let realWorkflow = ActorRef(kind: .workflow, identifier: "planner.daily")

        #expect(degraded.matchesIdentity(of: realWorkflow) == false)

        let registry = CapabilityLeaseRegistry()
        _ = await registry.grant(
            CapabilityLease(
                capability: .autoOrganization,
                reason: "planner may organize",
                grantedTo: realWorkflow,
                expiresAt: Date().addingTimeInterval(600)
            )
        )

        #expect(await registry.isGranted(.autoOrganization, to: realWorkflow))
        #expect(await registry.isGranted(.autoOrganization, to: degraded) == false)
    }

    @Test("the string bridge namespaces an unknown kind exactly like the JSON path")
    func stringBridgeNamespacesUnknownKind() {
        // `ReceiptActorDetail.kind` is a free `String` read back out of SwiftData, and the ref this
        // builds reaches `grantingLease(to:)`. Passing the identifier through verbatim here would
        // reintroduce the aliasing the JSON path prevents — via a different door.
        let detail = ReceiptActorDetail(kind: "quantumOracle", identifier: "planner.daily")

        let bridged = ActorRef(receiptActorDetail: detail)
        let decoded = try? JSONDecoder().decode(
            ActorRef.self,
            from: Data(#"{"kind":"quantumOracle","identifier":"planner.daily"}"#.utf8)
        )

        #expect(bridged.identifier == "unrecognized-kind:quantumOracle:planner.daily")
        #expect(bridged.identityKey == decoded?.identityKey)
    }

    @Test("a bridged unknown kind cannot claim a real workflow's lease")
    func bridgedUnknownKindDoesNotAliasARealWorkflow() async {
        let degraded = ActorRef(
            receiptActorDetail: ReceiptActorDetail(kind: "quantumOracle", identifier: "planner.daily")
        )
        let realWorkflow = ActorRef(kind: .workflow, identifier: "planner.daily")

        let registry = CapabilityLeaseRegistry()
        _ = await registry.grant(
            CapabilityLease(
                capability: .autoOrganization,
                reason: "planner may organize",
                grantedTo: realWorkflow,
                expiresAt: Date().addingTimeInterval(600)
            )
        )

        #expect(await registry.isGranted(.autoOrganization, to: realWorkflow))
        #expect(await registry.isGranted(.autoOrganization, to: degraded) == false)
    }

    @Test("the string bridge preserves a known kind unchanged")
    func stringBridgePreservesKnownKinds() {
        for kind in ActorKind.allCases {
            let bridged = ActorRef(
                receiptActorDetail: ReceiptActorDetail(kind: kind.rawValue, identifier: "x")
            )
            #expect(bridged.kind == kind)
            #expect(bridged.identifier == "x")
        }
    }

    @Test("an unknown inference locality degrades instead of dropping the actor")
    func unknownInferenceLocalityDegrades() throws {
        // The tolerance has to reach the nested type too: a throw from `InferenceProvenance`
        // propagates out of `ActorRef` and deletes the whole row, which is the exact failure the
        // unknown-kind handling exists to prevent.
        let actor = try decode(
            #"{"kind":"model","identifier":"m1","inference":{"locality":"hybrid","provider":"acme"}}"#
        )

        #expect(actor.kind == .model)
        #expect(actor.identifier == "m1")
        // Degrades to `.remote`, never `.local`: the value drives a user-facing privacy claim, and
        // only the conservative direction is safe to be wrong in.
        #expect(actor.inference?.locality == .remote)
        #expect(actor.inference?.provider == "acme")
    }

    @Test("every known kind still decodes to itself")
    func knownKindsAreUnaffected() throws {
        for kind in ActorKind.allCases {
            let actor = try decode(#"{"kind":"\#(kind.rawValue)","identifier":"x"}"#)
            #expect(actor.kind == kind)
            #expect(actor.identifier == "x")
            #expect(actor.displayName == nil)
        }
    }

    @Test("a full payload still round-trips unchanged")
    func fullPayloadRoundTrips() throws {
        let original = ActorRef.model(
            identifier: "foundation.on-device",
            inference: InferenceProvenance(locality: .local, provider: "apple", modelClass: "afm")
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ActorRef.self, from: data)

        #expect(decoded == original)
    }

    @Test("a worklog entry carrying an unknown actor kind survives the store")
    func worklogEntryWithUnknownActorKindSurvives() throws {
        // The end-to-end version of the failure: before tolerance, this row vanished entirely.
        let json = Data("""
        {
            "id": "5F7E4C6A-0000-4000-8000-000000000077",
            "correlationID": "corr-1",
            "toolID": "write",
            "event": { "blocked": { "reason": "nope" } },
            "actor": { "kind": "quantumOracle", "identifier": "oracle.1" },
            "timestamp": 715000000
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(WorkflowStepLog.self, from: json)

        #expect(decoded.correlationID == "corr-1")
        #expect(decoded.actor.kind == .workflow)
        #expect(decoded.actor.displayName == "Unrecognized actor (quantumOracle)")
    }
}

/// The `.model` ⇒ provenance invariant, pinned on *both* reconstruction paths.
///
/// It used to hold on neither: JSON `init(from:)` assigned the stored properties directly and so ran
/// none of the checked initializer's preconditions, producing a `.model` actor with no provenance,
/// while `init(receiptActorDetail:)` routed through the checked initializer and trapped on the same
/// row — aborting the process on the path that reads history. These tests exist so the two paths
/// cannot drift apart again.
@Suite("Model actor provenance is reconstructed, never trapped on")
struct ActorRefModelProvenanceTests {
    @Test("a persisted model actor with no provenance decodes instead of trapping")
    func jsonModelWithoutProvenanceDegrades() throws {
        let actor = try JSONDecoder().decode(
            ActorRef.self,
            from: Data(#"{"kind":"model","identifier":"m1"}"#.utf8)
        )

        #expect(actor.kind == .model)
        #expect(actor.identifier == "m1")
        // Conservative direction only: claiming inputs left the device is a harmless overstatement,
        // where the reverse would be a false privacy guarantee.
        #expect(actor.inference?.locality == .remote)
        #expect(actor.inference?.provider == nil)
    }

    @Test("a receipt row for a model actor with no provenance bridges instead of trapping")
    func bridgedModelWithoutProvenanceDegrades() {
        // This is the row that aborted the whole test process: `ReceiptActorDetail.kind` is a free
        // `String` out of SwiftData, so "model" with no locality column is reachable from disk.
        let bridged = ActorRef(receiptActorDetail: ReceiptActorDetail(kind: "model", identifier: "m1"))

        #expect(bridged.kind == .model)
        #expect(bridged.identifier == "m1")
        #expect(bridged.inference?.locality == .remote)
    }

    @Test("both paths agree on every kind, with and without provenance")
    func bothPathsAgreeOnEveryKind() throws {
        for kind in ActorKind.allCases {
            let bridged = ActorRef(
                receiptActorDetail: ReceiptActorDetail(kind: kind.rawValue, identifier: "x")
            )
            let decoded = try JSONDecoder().decode(
                ActorRef.self,
                from: Data(#"{"kind":"\#(kind.rawValue)","identifier":"x"}"#.utf8)
            )

            #expect(bridged == decoded, "paths disagree for \(kind.rawValue)")
            #expect(bridged.kind == kind)
            // The invariant the checked initializer claims to enforce now actually holds of values
            // built by both read paths, which is what lets that precondition stay on.
            #expect((kind == .model) == (bridged.inference != nil))
        }
    }

    @Test("a bridged model actor keeps recorded provenance rather than being degraded")
    func bridgePreservesRecordedProvenance() {
        let original = ActorRef.model(
            identifier: "foundation.on-device",
            inference: InferenceProvenance(locality: .local, provider: "apple", modelClass: "afm")
        )

        #expect(ActorRef(receiptActorDetail: original.receiptActorDetail) == original)
    }

    @Test("an unrecognized locality on a receipt row keeps its provider instead of losing provenance")
    func bridgeDegradesUnknownLocalityWithoutLosingProvider() {
        // Previously this flat-mapped to nil: the provider was dropped *and* a model actor came back
        // with no provenance at all, which is what the checked initializer then trapped on.
        let bridged = ActorRef(
            receiptActorDetail: ReceiptActorDetail(
                kind: "model",
                identifier: "m1",
                inferenceLocality: "hybrid",
                inferenceProvider: "acme",
                inferenceModelClass: "mystery"
            )
        )

        #expect(bridged.inference?.locality == .remote)
        #expect(bridged.inference?.provider == "acme")
        #expect(bridged.inference?.modelClass == "mystery")
    }

    @Test("a non-human actor with no identifier stays anonymous instead of trapping")
    func identifierlessNonHumanActorStaysAnonymous() {
        // Legacy rows predate the identifier field, and `identityKey` already resolves an anonymous
        // ref to `kind#anonymous`, which cannot alias a real actor's grant.
        let bridged = ActorRef(receiptActorDetail: ReceiptActorDetail(kind: "workflow"))

        #expect(bridged.kind == .workflow)
        #expect(bridged.identifier == nil)
        #expect(bridged.identityKey == "workflow#anonymous")
    }
}
