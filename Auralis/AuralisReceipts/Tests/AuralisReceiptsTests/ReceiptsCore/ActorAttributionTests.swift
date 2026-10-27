import AuralisFoundation
import Foundation
@testable import AuralisReceipts
@testable import AuralisRuntime
import Testing

/// Pins the *serialized* shape of `ActorRef` (P0.5-601).
///
/// `ActorRef` is embedded in durable JSON blobs — worklog step logs and execution records — and those
/// blobs are decoded with `try?`, which means a renamed case or coding key silently drops history
/// rather than failing loudly. Round-trip tests cannot catch that: they encode and decode with the
/// same (renamed) symbols and pass. These tests assert against literals instead.
@Suite("ActorKind serialization stability")
struct ActorKindStabilityTests {
    @Test("the six required kinds exist and no more")
    func exactlySixKinds() {
        #expect(ActorKind.allCases.count == 6)
        #expect(Set(ActorKind.allCases) == [.human, .operatorAgent, .plugin, .workflow, .scheduledRoutine, .model])
    }

    /// Literal raw values, not `Kind.x.rawValue` comparisons — the latter compares the enum to itself
    /// and passes through any rename.
    @Test("raw values are frozen wire format")
    func rawValuesAreFrozen() {
        #expect(ActorKind.human.rawValue == "human")
        #expect(ActorKind.operatorAgent.rawValue == "operator")
        #expect(ActorKind.plugin.rawValue == "plugin")
        #expect(ActorKind.workflow.rawValue == "workflow")
        #expect(ActorKind.scheduledRoutine.rawValue == "scheduledRoutine")
        #expect(ActorKind.model.rawValue == "model")

        #expect(InferenceLocality.local.rawValue == "local")
        #expect(InferenceLocality.remote.rawValue == "remote")
    }

    /// Guards the defect class where a trust surface renders `kind.rawValue` or
    /// `String(describing: kind)` and shows the person "operator" or the Swift case name
    /// `operatorAgent`. Every kind must have a distinct, presentable title that is not the wire value.
    @Test("every kind has a user-facing title distinct from its wire value")
    func displayTitlesAreNeverRawValues() {
        for kind in ActorKind.allCases {
            #expect(kind.displayTitle != kind.rawValue, "\(kind) leaks its wire value as a display title")
            #expect(kind.displayTitle != String(describing: kind), "\(kind) leaks its Swift case name")
            #expect(kind.displayTitle.first?.isUppercase == true, "\(kind) title is not presentable")
        }
        #expect(Set(ActorKind.allCases.map(\.displayTitle)).count == ActorKind.allCases.count)
    }

    @Test("every kind decodes from its persisted raw value", arguments: [
        ("human", ActorKind.human),
        ("operator", ActorKind.operatorAgent),
        ("plugin", ActorKind.plugin),
        ("workflow", ActorKind.workflow),
        ("scheduledRoutine", ActorKind.scheduledRoutine),
        ("model", ActorKind.model)
    ])
    func decodesFromFixedFixture(rawValue: String, expected: ActorKind) throws {
        let json = Data(#"{"kind":"\#(rawValue)","identifier":"id-1"}"#.utf8)
        let decoded = try JSONDecoder().decode(ActorRef.self, from: json)
        #expect(decoded.kind == expected)
        #expect(decoded.identifier == "id-1")
    }

    @Test("full model actor decodes from a hand-written payload")
    func decodesFullModelFixture() throws {
        let json = Data(#"""
        {
          "kind": "model",
          "identifier": "com.auralis.planner",
          "displayName": "Planner",
          "inference": { "locality": "remote", "provider": "anthropic", "modelClass": "opus" }
        }
        """#.utf8)

        let decoded = try JSONDecoder().decode(ActorRef.self, from: json)
        #expect(decoded.kind == .model)
        #expect(decoded.identifier == "com.auralis.planner")
        #expect(decoded.displayName == "Planner")
        #expect(decoded.inference?.locality == .remote)
        #expect(decoded.inference?.provider == "anthropic")
        #expect(decoded.inference?.modelClass == "opus")
    }

    /// Worklogs and execution records written before the optional fields existed must still decode,
    /// or reopening the store drops those entries.
    @Test("legacy payload with only a kind still decodes")
    func decodesLegacyMinimalFixture() throws {
        let json = Data(#"{"kind":"scheduledRoutine"}"#.utf8)
        let decoded = try JSONDecoder().decode(ActorRef.self, from: json)
        #expect(decoded.kind == .scheduledRoutine)
        #expect(decoded.identifier == nil)
        #expect(decoded.displayName == nil)
        #expect(decoded.inference == nil)
    }

    /// `AuralisCrypto` is a dependency-free leaf, so `ReceiptActorDetail.kind` is a plain
    /// `String` mirroring `ActorKind`'s raw values. Nothing but this test keeps the two in step.
    @Test("every kind survives the ReceiptActorDetail string mirror")
    func mirrorsIntoReceiptActorDetail() {
        for kind in ActorKind.allCases {
            // Model actors are constructed with provenance because the checked initializer requires
            // it — this is a programmatic caller, so the precondition applies rather than the
            // degrade the two tolerant read paths use.
            let actor = ActorRef(
                kind: kind,
                identifier: "id",
                inference: kind == .model ? .local() : nil
            )
            let detail = actor.receiptActorDetail
            #expect(detail.kind == kind.rawValue)
            #expect(ActorKind(rawValue: detail.kind) == kind, "\(kind) does not survive the string mirror")
        }
    }
}

/// `ActorRef` identity is kind + identifier. `displayName` and `inference` are presentation and
/// telemetry, and must never decide whether a capability grant or denial applies.
@Suite("ActorRef identity")
struct ActorRefIdentityTests {
    @Test("a display name does not change identity")
    func displayNameDoesNotAffectIdentity() {
        let bare = ActorRef(kind: .scheduledRoutine, identifier: "morning.brief")
        let named = ActorRef(kind: .scheduledRoutine, identifier: "morning.brief", displayName: "Morning Brief")

        #expect(bare != named, "structural equality should still see these as different values")
        #expect(bare.matchesIdentity(of: named))
        #expect(named.matchesIdentity(of: bare))
        #expect(bare.identityKey == named.identityKey)
    }

    /// The other half of the contract: `inference` is telemetry about *how* work was done and must
    /// not participate in identity either. Without this, folding `inference` back into `identityKey`
    /// would pass every other test — the same model routed locally once and remotely once would stop
    /// matching its own grant.
    @Test("inference provenance does not change identity")
    func inferenceDoesNotAffectIdentity() {
        let base = ActorRef.model(identifier: "planner.model", inference: .local())
        let local = ActorRef.model(identifier: "planner.model", inference: .local(modelClass: "foundation"))
        let remote = ActorRef.model(
            identifier: "planner.model",
            inference: InferenceProvenance(locality: .remote, provider: "anthropic", modelClass: "opus")
        )

        #expect(local != remote, "structural equality should still see these as different values")
        #expect(local.matchesIdentity(of: remote))
        #expect(local.matchesIdentity(of: base))
        #expect(local.identityKey == remote.identityKey)
        #expect(local.identityKey == base.identityKey)
    }

    /// Identifier-less actors key by kind alone — there is nothing else to distinguish them by — but
    /// an empty identifier must not alias the anonymous case.
    @Test("anonymous and empty-identifier actors are distinct")
    func anonymousAndEmptyIdentifierDoNotAlias() {
        let anonymous = ActorRef(kind: .human)
        let empty = ActorRef(kind: .human, identifier: "")

        #expect(anonymous.matchesIdentity(of: empty) == false)
        #expect(anonymous.matchesIdentity(of: ActorRef(kind: .human, displayName: "Someone")))
        // Built through the tolerant read path rather than the checked initializer: an anonymous
        // *non-human* actor is only reachable by reading a legacy row back, which is precisely the
        // case that must not alias the anonymous human.
        let anonymousWorkflow = ActorRef.reconstructed(
            rawKind: "workflow",
            identifier: nil,
            displayName: nil,
            inference: nil
        )
        #expect(anonymous.matchesIdentity(of: anonymousWorkflow) == false)
    }

    @Test("kind and identifier both participate in identity")
    func kindAndIdentifierDistinguishActors() {
        let routine = ActorRef(kind: .scheduledRoutine, identifier: "a")
        #expect(routine.matchesIdentity(of: ActorRef(kind: .scheduledRoutine, identifier: "b")) == false)
        #expect(routine.matchesIdentity(of: ActorRef(kind: .workflow, identifier: "a")) == false)
    }

    @Test("a lease still grants when the requesting actor carries a display name")
    func leaseMatchesOnIdentityNotDisplayName() async {
        let start = Date()
        let registry = CapabilityLeaseRegistry()
        // Mission Control grants against an identifier-only ref…
        let granted = ActorRef(kind: .scheduledRoutine, identifier: "morning.brief")
        // …while the runtime fires the routine with its human-readable name attached.
        let firing = ActorRef(kind: .scheduledRoutine, identifier: "morning.brief", displayName: "Morning Brief")

        await registry.grant(
            CapabilityLease(
                capability: .playbackQueue,
                grantedTo: granted,
                grantedAt: start,
                expiresAt: start.addingTimeInterval(1200)
            )
        )

        #expect(await registry.isGranted(.playbackQueue, to: firing, at: start.addingTimeInterval(1)))
    }

    @Test("a restriction still denies when the checked actor carries a display name")
    func restrictionMatchesOnIdentityNotDisplayName() async {
        let start = Date()
        let registry = CapabilityLeaseRegistry()
        let denied = ActorRef(kind: .scheduledRoutine, identifier: "morning.brief")
        let firing = ActorRef(kind: .scheduledRoutine, identifier: "morning.brief", displayName: "Morning Brief")

        await registry.deny(
            CapabilityRestriction(
                kind: .walletAccess,
                reason: "No wallet access for routines.",
                appliesTo: denied,
                createdAt: start
            )
        )

        // Without identity matching the display name would let the routine slip past its own denial.
        #expect(await registry.isDenied(.signMessage, to: firing, at: start.addingTimeInterval(1)))
        #expect(await registry.isGranted(.signMessage, to: firing, at: start.addingTimeInterval(1)) == false)
    }

    @Test("a restriction scoped to another actor does not deny")
    func restrictionStaysScopedToItsActor() async {
        let start = Date()
        let registry = CapabilityLeaseRegistry()
        await registry.deny(
            CapabilityRestriction(
                kind: .walletAccess,
                reason: "No wallet access for this routine.",
                appliesTo: ActorRef(kind: .scheduledRoutine, identifier: "morning.brief"),
                createdAt: start
            )
        )

        let other = ActorRef(kind: .scheduledRoutine, identifier: "evening.digest")
        #expect(await registry.isDenied(.signMessage, to: other, at: start.addingTimeInterval(1)) == false)
    }
}

/// The "under what authority" leg (P0.5-601/602): the registry must hand back *which* grant said
/// yes, and the governed pipeline must record it on the receipt and the worklog.
@Suite("AuthorityRef")
struct AuthorityRefTests {
    @Test("source raw values are frozen wire format")
    func sourceRawValuesAreFrozen() {
        #expect(AuthorityRef.Source.allCases.count == 3)
        #expect(AuthorityRef.Source.lease.rawValue == "lease")
        #expect(AuthorityRef.Source.humanApproval.rawValue == "humanApproval")
        #expect(AuthorityRef.Source.policyDefault.rawValue == "policyDefault")
    }

    @Test("an authority built from a lease carries the whole grant")
    func authorityFromLeaseCarriesGrant() {
        let start = Date()
        let lease = CapabilityLease(
            capability: .playbackQueue,
            reason: "Planner may queue playback for 20 minutes.",
            grantedTo: ActorRef(kind: .workflow, identifier: "planner"),
            grantedAt: start,
            expiresAt: start.addingTimeInterval(1200)
        )
        let authority = AuthorityRef(lease: lease)

        #expect(authority.source == .lease)
        #expect(authority.leaseID == lease.id)
        #expect(authority.capability == .playbackQueue)
        #expect(authority.scope == .execution)
        #expect(authority.reason == "Planner may queue playback for 20 minutes.")
        #expect(authority.expiresAt == lease.expiresAt)
    }

    @Test("the registry returns which lease granted, not just whether one did")
    func registryReturnsTheGrantingLease() async {
        let start = Date()
        let registry = CapabilityLeaseRegistry()
        let planner = ActorRef(kind: .workflow, identifier: "planner")
        let lease = await registry.grant(
            CapabilityLease(
                capability: .playbackQueue,
                grantedTo: planner,
                grantedAt: start,
                expiresAt: start.addingTimeInterval(1200)
            )
        )

        let granting = await registry.grantingLease(.playbackQueue, to: planner, at: start.addingTimeInterval(1))
        #expect(granting?.id == lease.id)

        // A denial withdraws the authority, not just the boolean.
        await registry.deny(
            CapabilityRestriction(
                kind: .capability(.playbackQueue),
                reason: "Paused by operator.",
                appliesTo: planner,
                createdAt: start
            )
        )
        #expect(await registry.grantingLease(.playbackQueue, to: planner, at: start.addingTimeInterval(2)) == nil)
        #expect(await registry.isGranted(.playbackQueue, to: planner, at: start.addingTimeInterval(2)) == false)
    }

    @Test("the newest qualifying grant is the recorded authority")
    func newestGrantWins() async {
        let start = Date()
        let registry = CapabilityLeaseRegistry()
        let planner = ActorRef(kind: .workflow, identifier: "planner")
        _ = await registry.grant(
            CapabilityLease(
                capability: .playbackQueue,
                reason: "Older grant.",
                grantedTo: planner,
                grantedAt: start,
                expiresAt: start.addingTimeInterval(1200)
            )
        )
        let newer = await registry.grant(
            CapabilityLease(
                capability: .playbackQueue,
                reason: "Newer grant.",
                grantedTo: planner,
                grantedAt: start.addingTimeInterval(10),
                expiresAt: start.addingTimeInterval(1200)
            )
        )

        let granting = await registry.grantingLease(.playbackQueue, to: planner, at: start.addingTimeInterval(20))
        #expect(granting?.id == newer.id)
        #expect(granting?.reason == "Newer grant.")
    }

    @Test("authority survives a fixed-fixture decode")
    func decodesFromFixture() throws {
        let json = Data(#"""
        {
          "source": "lease",
          "leaseID": "6C7E4C3E-1F2B-4E6E-9A4C-2F1B3D5E7A90",
          "capability": "playback_queue",
          "scope": "execution",
          "reason": "Planner may queue playback."
        }
        """#.utf8)

        let decoded = try JSONDecoder().decode(AuthorityRef.self, from: json)
        #expect(decoded.source == .lease)
        #expect(decoded.leaseID == UUID(uuidString: "6C7E4C3E-1F2B-4E6E-9A4C-2F1B3D5E7A90"))
        #expect(decoded.capability == .playbackQueue)
        #expect(decoded.scope == .execution)
        #expect(decoded.expiresAt == nil)
    }

    @Test("the receipt bridge preserves every authority field")
    func bridgesToReceiptAuthorityDetail() {
        let start = Date()
        let lease = CapabilityLease(
            capability: .signMessage,
            reason: "One signature.",
            grantedTo: .human,
            grantedAt: start,
            expiresAt: start.addingTimeInterval(60)
        )
        let detail = AuthorityRef(lease: lease).receiptAuthorityDetail

        #expect(detail.source == "lease")
        #expect(detail.leaseID == lease.id.uuidString)
        // The persisted capability is `CapabilityID`'s own snake_case wire value, not the case name.
        #expect(detail.capability == "sign_message")
        #expect(detail.scope == "account")
        #expect(detail.reason == "One signature.")
        #expect(detail.expiresAt == lease.expiresAt)
    }
}

/// The `ModelRoute` → attribution bridge, so routing telemetry and recorded provenance can't drift.
@Suite("ModelRoute attribution bridge")
struct ModelRouteAttributionTests {
    @Test("provenance is built from the route that ran")
    func provenanceMirrorsRoute() {
        let route = ModelRoute(
            id: "remote.opus",
            provider: "anthropic",
            modelClass: "opus",
            locality: .remote
        )
        let provenance = InferenceProvenance(route: route)

        #expect(provenance.locality == .remote)
        #expect(provenance.provider == "anthropic")
        #expect(provenance.modelClass == "opus")
        #expect(provenance.privacyImpact == InferenceLocality.remote.privacyImpact)
    }

    @Test("model actor from a route carries kind, identity, and provenance")
    func modelActorFromRoute() {
        let route = ModelRoute(
            id: "local.afm",
            provider: "apple",
            modelClass: "foundation",
            locality: .local
        )
        let actor = ActorRef.model(identifier: "planner.model", route: route)

        #expect(actor.kind == .model)
        #expect(actor.identifier == "planner.model")
        #expect(actor.inference == InferenceProvenance(route: route))
        #expect(actor.receiptActorDetail.inferenceLocality == "local")
    }
}

/// Pins the "which one" half of an attribution label against an **empty** `displayName`.
///
/// `displayLabel`/`attributionLabel` resolve the name through `displayName ?? identifier`-style
/// precedence. `??` short-circuits on any non-`nil` value, so a `displayName` of `""` discarded a
/// perfectly good `identifier` and both labels collapsed to a bare kind title — dropping exactly the
/// half these surfaces exist to show. An empty string reaches here easily: `init` trims and
/// precondition-checks `identifier` but applies neither to `displayName`, and the decoder accepts
/// whatever the persisted blob carries.
///
/// Added in audit Round 18. Both labels were untested against this input: neutering the non-empty
/// filter left AuralisRuntime 281/281 and AuralisMissionControl 126/126 green.
@Suite("Actor attribution falls back past an empty display name")
struct ActorAttributionEmptyNameTests {
    private let routine = ActorRef(
        kind: .scheduledRoutine,
        identifier: "morning-brief",
        displayName: ""
    )

    @Test("an empty display name falls through to the identifier rather than to the bare kind")
    func emptyDisplayNameFallsBackToIdentifier() {
        #expect(routine.displayLabel == "morning-brief")
        #expect(routine.attributionLabel == "\(ActorKind.scheduledRoutine.displayTitle) — morning-brief")
        #expect(routine.attributionLabel != ActorKind.scheduledRoutine.displayTitle)
    }

    @Test("a present display name still wins over the identifier")
    func nonEmptyDisplayNameStillWins() {
        let named = ActorRef(kind: .scheduledRoutine, identifier: "morning-brief", displayName: "Morning Brief")

        #expect(named.displayLabel == "Morning Brief")
        #expect(named.attributionLabel == "\(ActorKind.scheduledRoutine.displayTitle) — Morning Brief")
    }

    /// With no name of any kind the bare kind title is the correct answer, not a regression — the
    /// fallback must not invent one.
    @Test("a human actor with neither name renders as the kind alone")
    func noNameRendersKindOnly() {
        let anonymous = ActorRef(kind: .human)

        #expect(anonymous.displayLabel == ActorKind.human.displayTitle)
        #expect(anonymous.attributionLabel == ActorKind.human.displayTitle)
    }

    /// An empty `displayName` that survived a persisted blob must behave the same as one passed to
    /// `init` — the decoder is the likelier source of it.
    @Test("an empty display name decoded from a persisted blob falls back identically")
    func emptyDisplayNameFromDecodedBlobFallsBack() throws {
        let json = Data(#"{"kind":"scheduledRoutine","identifier":"morning-brief","displayName":""}"#.utf8)
        let decoded = try JSONDecoder().decode(ActorRef.self, from: json)

        #expect(decoded.attributionLabel == "\(ActorKind.scheduledRoutine.displayTitle) — morning-brief")
    }
}
