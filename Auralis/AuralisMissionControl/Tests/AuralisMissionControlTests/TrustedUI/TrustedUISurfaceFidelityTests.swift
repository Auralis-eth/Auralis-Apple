import AuralisFoundation
import Foundation
import AuralisRuntime
import Testing
@testable import AuralisMissionControl

/// These surfaces are where a person decides whether to authorise something, so the properties
/// under test are all forms of one question: does the screen say what is actually being approved?
@Suite("ApprovalSheet — the sheet states what it authorises")
struct ApprovalSheetDisclosureTests {

    private func proposal(
        intent: String = "sign a message",
        impact: ActionImpactClass = .highRisk,
        parameters: [String: String] = [:]
    ) -> ActionProposal {
        ActionProposal(
            actor: .human,
            intent: intent,
            capability: .signMessage,
            impact: impact,
            parameters: parameters
        )
    }

    @Test("every parameter is rendered, sorted by key")
    func everyParameterIsRendered() {
        let rows = ApprovalSheet.parameterRows(
            proposal(parameters: ["chain": "1", "address": "0xabc", "amount": "250"])
        )

        #expect(rows.map(\.id) == ["address", "amount", "chain"])
        #expect(rows.map(\.value) == ["0xabc", "250", "1"])
    }

    /// The governance-stamped freshness keys are parameters too. Filtering the list down to the
    /// keys someone considered interesting is how a parameter that matters goes missing.
    @Test("nothing is filtered out, including the boundary-stamped freshness keys")
    func freshnessParametersAreNotFiltered() {
        let rows = ApprovalSheet.parameterRows(
            proposal(parameters: [
                StandardCheckParameterKey.contextRefreshedAt: "1759500000.0",
                StandardCheckParameterKey.freshnessEvaluatedAt: "1759536000.0",
                "address": "0xabc"
            ])
        )

        #expect(rows.count == 3)
        #expect(rows.map(\.id).contains(StandardCheckParameterKey.contextRefreshedAt))
        #expect(rows.map(\.id).contains(StandardCheckParameterKey.freshnessEvaluatedAt))
    }

    /// Truncating the tail of an address is the classic way an approval surface shows the wrong
    /// destination while looking right: the prefix a person recognises survives, the bytes that
    /// decide where the funds go do not.
    @Test("addresses and amounts are shown whole, never shortened")
    func valuesAreNotTruncated() {
        let address = "0x1111111111111111111111111111111111111111"
        let lookalike = "0x1111111111111111111111111111111111119999"
        let amount = "115792089237316195423570985008687907853269984665640564039457584007913129639935"

        let rows = ApprovalSheet.parameterRows(
            proposal(parameters: ["address": lookalike, "amount": amount])
        )

        #expect(rows.first { $0.id == "address" }?.value == lookalike)
        #expect(rows.first { $0.id == "amount" }?.value == amount)
        // The two addresses agree for 36 characters; anything that shortens the value renders them
        // identically on a surface whose job is telling them apart.
        #expect(rows.first { $0.id == "address" }?.value != address)
    }

    /// `intent` is free text written by the actor being governed. It is the only thing the sheet
    /// used to show about the target, so prose and execution could disagree silently.
    @Test("a proposal whose prose disagrees with its target still shows the target")
    func prosePromiseDoesNotHideTheRealTarget() {
        let attacker = "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        let rows = ApprovalSheet.parameterRows(
            proposal(
                intent: "Send 0.1 ETH to Alice",
                parameters: ["address": attacker, "amount": "100000000000000000000"]
            )
        )

        #expect(rows.first { $0.id == "address" }?.value == attacker)
        #expect(rows.first { $0.id == "amount" }?.value == "100000000000000000000")
    }

    @Test("a proposal naming no target produces no parameter rows")
    func noParametersProducesNoRows() {
        #expect(ApprovalSheet.parameterRows(proposal()).isEmpty)
    }
}

@Suite("PermissionCard — a lease is only authority while it is live")
struct PermissionLeaseStatusTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func lease(
        grantedAt: TimeInterval,
        expiresAt: TimeInterval,
        revokedAt: TimeInterval? = nil,
        grantedTo: ActorRef = .human
    ) -> CapabilityLease {
        CapabilityLease(
            capability: .signMessage,
            grantedTo: grantedTo,
            grantedAt: now.addingTimeInterval(grantedAt),
            expiresAt: now.addingTimeInterval(expiresAt),
            revokedAt: revokedAt.map(now.addingTimeInterval)
        )
    }

    @Test("lease standing is classified, not assumed", arguments: [
        (-60.0, 1_200.0, nil as TimeInterval?, PermissionLeaseStatus.granted),
        (-60.0, 1_200.0, -300.0, .revoked),
        (-3_600.0, -120.0, nil, .expired),
        (600.0, 1_200.0, nil, .scheduled)
    ])
    func leaseStatusClassification(
        grantedAt: TimeInterval,
        expiresAt: TimeInterval,
        revokedAt: TimeInterval?,
        expected: PermissionLeaseStatus
    ) {
        let model = PermissionCardModel(
            capability: .signMessage,
            lease: lease(grantedAt: grantedAt, expiresAt: expiresAt, revokedAt: revokedAt),
            now: now
        )

        #expect(model.leaseStatus == expected)
    }

    /// A revoked lease keeps the future `expiresAt` it was granted with, so "a lease exists" and
    /// "the capability is granted" are different statements. The card previously rendered every
    /// supplied lease as `"<scope> — expires <relative expiresAt>"`, which reads as live authority
    /// for a grant that was withdrawn five minutes ago.
    @Test("a lease revoked before its expiry never reads as a live grant")
    func revokedLeaseDoesNotReadAsLive() throws {
        let model = PermissionCardModel(
            capability: .signMessage,
            lease: lease(grantedAt: -60, expiresAt: 1_200, revokedAt: -300),
            now: now
        )

        #expect(model.leaseStatus == .revoked)
        #expect(model.leaseStatus?.authorizesNow == false)
        let summary = try #require(model.leaseSummary)
        #expect(summary.contains("revoked"))
        #expect(!summary.contains("expires"))
    }

    /// Mirrors `CapabilityLease.isActive(at:)`, which only honours a revocation once `now` reaches
    /// it. Testing for the column's presence instead would mark a scheduled future revocation as
    /// already withdrawn.
    @Test("a revocation dated in the future has not taken effect yet")
    func futureRevocationIsNotYetInEffect() {
        let future = lease(grantedAt: -60, expiresAt: 1_200, revokedAt: 600)
        let model = PermissionCardModel(capability: .signMessage, lease: future, now: now)

        #expect(model.leaseStatus == .granted)
        #expect(future.isActive(at: now))
    }

    @Test("an expired lease is stated as expired rather than as a grant that expires")
    func expiredLeaseReadsAsExpired() {
        let model = PermissionCardModel(
            capability: .signMessage,
            lease: lease(grantedAt: -3_600, expiresAt: -120),
            now: now
        )

        #expect(model.leaseStatus?.authorizesNow == false)
        #expect(model.leaseSummary?.contains("expired") == true)
    }

    /// Guards the next case someone adds to the enum: a new standing defaults to "not authority"
    /// only if `authorizesNow` keeps naming `granted` explicitly.
    @Test("only a granted lease authorises")
    func onlyGrantedAuthorises() {
        let authorising = PermissionLeaseStatus.allCases.filter(\.authorizesNow)
        #expect(authorising == [.granted])
    }

    /// "Account scope" says what the grant reaches, not who holds it.
    @Test("the lease row names the holder, not just the scope")
    func leaseNamesItsHolder() {
        let agent = ActorRef(kind: .operatorAgent, identifier: "op.brief")
        let model = PermissionCardModel(
            capability: .signMessage,
            lease: lease(grantedAt: -60, expiresAt: 1_200, grantedTo: agent),
            now: now
        )

        #expect(model.leaseSummary?.contains(agent.attributionLabel) == true)
        #expect(model.leaseSummary?.contains(CapabilityLeaseScope.account.displayTitle) == true)
    }

    @Test("a capability with no lease shows no lease row at all")
    func noLeaseNoRow() {
        let model = PermissionCardModel(capability: .signMessage, now: now)

        #expect(model.leaseSummary == nil)
        #expect(model.leaseStatus == nil)
    }
}

@Suite("Context redaction follows the payload, not the label")
struct TrustedUIContextRedactionTests {

    /// Builds the wire shape of a `ContextField` so a value and a `dataClass` that disagree can be
    /// constructed — the public initialisers deliberately cannot produce one, but
    /// `ContextField.init(from:)` accepts it.
    private struct WireField: Encodable {
        let key: String
        let value: ContextValue
        let dataClass: ContextDataClass
    }

    private func decoded(_ value: ContextValue, as dataClass: ContextDataClass) throws -> ContextField {
        let data = try JSONEncoder().encode(WireField(key: "addr", value: value, dataClass: dataClass))
        return try JSONDecoder().decode(ContextField.self, from: data)
    }

    /// `ContextField.init(from:)` only coerces a value to `.redacted` when the declared class is
    /// already `.sensitive`, so a bundle can arrive carrying an opaque vault handle under a
    /// `publicIdentifier` label. Keying the display rule on `dataClass` trusted the label to agree
    /// with the bytes and projected the handle straight onto the card.
    @Test("a vault reference mislabelled as public is still withheld")
    func mislabelledVaultReferenceIsWithheld() throws {
        let field = try decoded(.sensitiveReference("vault://seed-phrase"), as: .publicIdentifier)

        #expect(field.dataClass == .publicIdentifier)
        #expect(field.stringValue == "vault://seed-phrase")
        #expect(TrustedUIContextRedaction.displayValue(field) == TrustedUIContextRedaction.redactedPlaceholder)
    }

    /// "Nothing here" and "something here you may not see" are different facts on a surface whose
    /// job is making governed context visible; both used to render as the same em dash.
    @Test("a withheld value is distinguishable from an absent one")
    func withheldIsNotAbsent() throws {
        let withheld = try decoded(.redacted, as: .derived)
        let absent = ContextField(key: "addr", stringValue: nil, dataClass: .derived)

        #expect(TrustedUIContextRedaction.displayValue(withheld) == TrustedUIContextRedaction.redactedPlaceholder)
        #expect(TrustedUIContextRedaction.displayValue(absent) == TrustedUIContextRedaction.absentPlaceholder)
        #expect(TrustedUIContextRedaction.redactedPlaceholder != TrustedUIContextRedaction.absentPlaceholder)
    }

    @Test("plain text is shown for every class except sensitive", arguments: [
        ContextDataClass.publicIdentifier,
        .userProvided,
        .localPreference,
        .derived
    ])
    func plainTextPassesThrough(dataClass: ContextDataClass) {
        let field = ContextField(key: "addr", stringValue: "0xabc", dataClass: dataClass)

        #expect(TrustedUIContextRedaction.displayValue(field) == "0xabc")
    }

    @Test("a sensitive class withholds its value however it was supplied")
    func sensitiveClassAlwaysWithholds() throws {
        let viaInit = ContextField(key: "seed", stringValue: "abc", dataClass: .sensitive)
        let viaWire = try decoded(.text("abc"), as: .sensitive)

        #expect(TrustedUIContextRedaction.displayValue(viaInit) == TrustedUIContextRedaction.redactedPlaceholder)
        #expect(TrustedUIContextRedaction.displayValue(viaWire) == TrustedUIContextRedaction.redactedPlaceholder)
    }
}

@Suite("Field rows survive duplicate keys")
struct TrustedUIFieldRowTests {

    /// `ContextBundle` never rejects a repeated key, and `ForEach(_, id: \.key)` draws one row for
    /// a colliding pair — a second `address` field would simply not appear.
    @Test("a bundle carrying the same key twice renders both values")
    func duplicateContextKeysStayDistinctRows() {
        let bundle = ContextBundle(fields: [
            ContextField(key: "address", stringValue: "0xaaa", dataClass: .publicIdentifier),
            ContextField(key: "address", stringValue: "0xbbb", dataClass: .publicIdentifier)
        ])

        let rows = ContextBundleCard.rows(for: bundle)

        #expect(rows.count == 2)
        #expect(Set(rows.map(\.id)).count == 2)
        #expect(rows.map(\.value) == ["0xaaa", "0xbbb"])
    }

    @Test("rows carry the redacted value, never the raw one")
    func rowsRedact() {
        let bundle = ContextBundle(fields: [
            ContextField(key: "seed", stringValue: "correct horse", dataClass: .sensitive)
        ])

        let rows = ContextBundleCard.rows(for: bundle)

        #expect(rows.first?.value == TrustedUIContextRedaction.redactedPlaceholder)
        #expect(rows.first?.dataClass == ContextDataClass.sensitive.rawValue)
    }

    @Test("rows preserve the provenance shown beneath each value")
    func rowsCarryProvenance() {
        let refreshed = Date(timeIntervalSince1970: 1_700_000_000)
        let bundle = ContextBundle(fields: [
            ContextField(
                key: "address",
                stringValue: "0xabc",
                dataClass: .publicIdentifier,
                source: .walletStore,
                lastRefreshed: refreshed
            )
        ])

        let row = ContextBundleCard.rows(for: bundle).first

        #expect(row?.source == GovernedContextSource.walletStore.rawValue)
        #expect(row?.lastRefreshed == refreshed)
    }

    @Test("an empty bundle produces no rows, so the empty state is what shows")
    func emptyBundleProducesNoRows() {
        #expect(ContextBundleCard.rows(for: ContextBundle(fields: [])).isEmpty)
    }

    /// Pins why `ReceiptCard` iterates positionally: `Field.id` is the key, and a summary may hold
    /// the same key twice. If a future change makes ids unique this test should be revisited
    /// deliberately rather than by quietly dropping a row.
    @Test("receipt field ids collide on duplicate keys while both fields survive")
    func receiptFieldIDsCollideOnDuplicateKeys() {
        let summary = TrustedUIReceiptSummary(
            id: UUID(),
            title: "Approved spending",
            subtitle: "wallet",
            actorLabel: "You",
            timestamp: .now,
            fields: [
                .init(key: "amount", value: "1"),
                .init(key: "amount", value: "1000")
            ]
        )

        #expect(summary.fields.count == 2)
        #expect(Set(summary.fields.map(\.id)).count == 1)
    }
}

@Suite("Trusted UI accessibility contract")
struct TrustedUIA11yIDContractTests {

    @Test("identifiers are unique")
    func identifiersAreUnique() {
        #expect(Set(TrustedUIA11yID.all).count == TrustedUIA11yID.all.count)
    }

    @Test("identifiers are lowercased dot-namespaced under the trustedui area")
    func identifiersFollowTheConvention() {
        for identifier in TrustedUIA11yID.all {
            #expect(identifier == identifier.lowercased(), "\(identifier) is not lowercased")
            #expect(identifier.hasPrefix("trustedui."), "\(identifier) is outside the trustedui area")
            #expect(identifier.split(separator: ".").count >= 2, "\(identifier) is not dot-namespaced")
            #expect(!identifier.hasSuffix("."), "\(identifier) has an empty trailing component")
        }
    }

    /// Static members are invisible to `Mirror`, so completeness cannot be derived. The count is a
    /// deliberate tripwire: adding a constant without listing it in `all` fails here, which is also
    /// the moment to add it to AuraUI's mirror.
    @Test("`all` lists every declared identifier")
    func allListsEveryIdentifier() {
        let declared = [
            TrustedUIA11yID.approvalSurface,
            TrustedUIA11yID.approvalApprove,
            TrustedUIA11yID.approvalDeny,
            TrustedUIA11yID.approvalDefer,
            TrustedUIA11yID.approvalSubmitted,
            TrustedUIA11yID.approvalParameters,
            TrustedUIA11yID.draftEditor,
            TrustedUIA11yID.draftSave,
            TrustedUIA11yID.permissionCard,
            TrustedUIA11yID.permissionLease,
            TrustedUIA11yID.receiptCard,
            TrustedUIA11yID.contextBundleCard,
            TrustedUIA11yID.contextBundleEmpty,
            TrustedUIA11yID.riskBanner,
            TrustedUIA11yID.suggestionCard,
            TrustedUIA11yID.suggestionAction,
            TrustedUIA11yID.unavailable
        ]

        #expect(Set(TrustedUIA11yID.all) == Set(declared))
        #expect(TrustedUIA11yID.all.count == declared.count)
    }

    /// Every component the registry can produce must be addressable, or a UI test can assert a
    /// trust surface appeared without being able to name which one.
    @Test("every component kind the registry can produce has an identifier")
    func everyComponentKindIsAddressable() {
        let identifierByKind: [TrustedUIComponentRegistry.ComponentKind: String] = [
            .approvalSheet: TrustedUIA11yID.approvalSurface,
            .draftEditor: TrustedUIA11yID.draftEditor,
            .permissionCard: TrustedUIA11yID.permissionCard,
            .receiptCard: TrustedUIA11yID.receiptCard,
            .contextBundleCard: TrustedUIA11yID.contextBundleCard,
            .suggestionCard: TrustedUIA11yID.suggestionCard,
            .riskBanner: TrustedUIA11yID.riskBanner
        ]

        #expect(Set(identifierByKind.keys) == Set(TrustedUIComponentRegistry.ComponentKind.allCases))
        for identifier in identifierByKind.values {
            #expect(TrustedUIA11yID.all.contains(identifier))
        }
    }
}

@Suite("Risk level never flattens a distinction the impact class makes")
struct TrustedUIRiskLevelOrderingTests {

    /// A new `ActionImpactClass` mapped onto an existing level — the easy mistake being to reach
    /// for `.informational` — would render a more dangerous action with the vocabulary of a safer
    /// one. Collapsing two classes onto one level is that defect's signature.
    @Test("distinct impact classes never collapse onto the same risk level")
    func impactClassesDoNotCollapse() {
        let levels = ActionImpactClass.allCases.map(TrustedUIRiskLevel.init(impact:))

        #expect(Set(levels).count == ActionImpactClass.allCases.count)
    }

    @Test("risk rises monotonically with impact")
    func riskRisesWithImpact() {
        let ordered = ActionImpactClass.allCases.sorted()
        let severities = ordered.map { impact -> Int in
            let level = TrustedUIRiskLevel(impact: impact)
            return TrustedUIRiskLevel.allCases.firstIndex(of: level) ?? -1
        }

        #expect(severities == severities.sorted())
        #expect(severities.first == 0)
        #expect(severities.last == TrustedUIRiskLevel.allCases.count - 1)
    }

    /// The banner carries an icon and a worded title as well as a tint, so severity is never
    /// conveyed by colour alone.
    @Test("every risk level has a distinct worded title")
    func everyLevelIsWorded() {
        let titles = TrustedUIRiskLevel.allCases.map(\.title)

        #expect(Set(titles).count == TrustedUIRiskLevel.allCases.count)
        #expect(titles.allSatisfy { !$0.isEmpty })
    }
}

/// The tests above pin the mapping from a *declared* impact class, which is the half nothing was
/// wrong with. `ActionProposal.impact` is written by the actor being governed, and the sheet rendered
/// it verbatim — so these cover the other direction: what the surface shows when the declaration and
/// the capability disagree.
@Suite("Risk severity is floored by the capability, not taken from the proposer")
struct TrustedUIRiskFloorTests {

    private func proposal(
        capability: CapabilityID,
        impact: ActionImpactClass,
        intent: String = "Check balances"
    ) -> ActionProposal {
        ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: "op.balances"),
            intent: intent,
            capability: capability,
            impact: impact,
            parameters: ["address": "0x1111111111111111111111111111111111111111", "amount": "100"]
        )
    }

    /// The blocker. A grey `info.circle` "Read-only" banner above approve/deny/defer for an action
    /// that moves funds: the proposal says `approveSpending` and claims `.readOnly`, and no wallet
    /// capability has a read-only mode, so the claim is not merely optimistic but impossible.
    @Test("a wallet proposal declaring itself read-only still renders at the capability floor",
          arguments: [CapabilityID.approveSpending, .signMessage, .draftTransaction])
    func walletCapabilitiesAreFlooredToHighRisk(capability: CapabilityID) {
        let understated = proposal(capability: capability, impact: .readOnly)

        let rendered = ApprovalSheet.riskLevel(for: understated)

        #expect(rendered == .high)
        #expect(rendered.title == "High risk")
        // Named explicitly: "Read-only" is the string a person read off a spending approval.
        #expect(rendered.title != "Read-only")
        // And the floor is what made the difference — the declared class alone still reads benign.
        #expect(TrustedUIRiskLevel(impact: understated.impact) == .informational)
    }

    /// `musicExport` has no read-only mode either: producing an export always puts data somewhere
    /// else. Inspecting what *would* be exported is a different capability.
    @Test("an export declaring itself read-only renders as an external effect")
    func exportIsFlooredToExternalImpact() {
        let rendered = ApprovalSheet.riskLevel(for: proposal(capability: .musicExport, impact: .readOnly))

        #expect(rendered == .medium)
    }

    /// `max`, not replacement. A proposal may declare itself *more* dangerous than its capability
    /// requires — a bulk metadata rewrite, say — and the floor must not talk it back down.
    @Test("a declaration above the floor is preserved, not lowered to it")
    func floorNeverLowersADeclaration() {
        let overstated = proposal(capability: .audioPlayback, impact: .highRisk)

        #expect(ApprovalSheet.riskLevel(for: overstated) == .high)
        #expect(CapabilityImpactMapping.minimumImpact(for: .audioPlayback) == .readOnly)
    }

    /// `minimumImpact`, never `defaultImpact` — same signature, different meaning. `runPlugin` as a
    /// whole is `.externalImpact`, but a plugin run that only inspects local state reaches outside
    /// nothing, and `OperatorCatalog` really does declare such tools `.readOnly`. Flooring with the
    /// execute-impact would overstate those and send read-only work to the approval inbox.
    @Test("a genuinely read-only plugin run is not inflated by the execute impact")
    func readOnlyPluginRunIsNotOverstated() {
        let inspection = proposal(capability: .runPlugin, impact: .readOnly, intent: "Summarise local library")

        #expect(ApprovalSheet.riskLevel(for: inspection) == .informational)
        // The wrong function would have produced `.medium` here.
        #expect(TrustedUIRiskLevel(impact: CapabilityImpactMapping.defaultImpact(for: .runPlugin)) == .medium)
    }

    /// Delegation, not a second local implementation: the sheet must ask ``TrustedUIRiskLevel`` for
    /// the floored reading rather than keep its own copy of the rule, which is how this surface
    /// drifted from every other governed one in the first place.
    @Test("the sheet's level is the model's floored level, for every capability and declaration")
    func sheetDelegatesToTheFlooredInitializer() {
        for capability in CapabilityID.allCases {
            for impact in ActionImpactClass.allCases {
                let candidate = proposal(capability: capability, impact: impact)
                #expect(ApprovalSheet.riskLevel(for: candidate) == TrustedUIRiskLevel(proposal: candidate))
            }
        }
    }

    /// Whatever a proposal claims, the severity shown is never below the floor its capability sets.
    @Test("no capability/declaration pair can render below its floor")
    func nothingRendersBelowItsFloor() {
        func severity(_ level: TrustedUIRiskLevel) -> Int {
            TrustedUIRiskLevel.allCases.firstIndex(of: level) ?? -1
        }

        for capability in CapabilityID.allCases {
            for impact in ActionImpactClass.allCases {
                let floor = TrustedUIRiskLevel(impact: CapabilityImpactMapping.minimumImpact(for: capability))
                let rendered = ApprovalSheet.riskLevel(for: proposal(capability: capability, impact: impact))

                #expect(severity(rendered) >= severity(floor))
            }
        }
    }
}
