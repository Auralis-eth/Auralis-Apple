@_spi(ToolRegistration) @testable import AuralisOperators
@_spi(ToolRegistration) import AuralisRuntime
import Testing

/// Every operator the catalog ships, by id. Parameterizing on the ids rather than on a hand-written
/// list is the point: a new operator is covered by all of these the moment it is added, which is what
/// makes them contracts on the catalog instead of assertions about four particular tools.
private let allOperatorToolIDs = OperatorCatalog.all.map(\.tool.id)

@Suite("Operator catalog contract")
struct OperatorCatalogContractTests {
    /// A declared impact must never sit below the floor its *capability* makes possible.
    ///
    /// This is the guard against the under-gating half of the `minimumImpact` / `defaultImpact`
    /// confusion. The two are different functions with the same signature and return type, and
    /// `minimumImpact` for a wallet capability is `.highRisk` because there is no way to sign,
    /// approve, or draft that only reads. So a future operator naming `draftTransaction` while
    /// declaring itself `.readOnly` would be a proposal that `requiresConfirmation == false` clears
    /// unattended — and `RuntimeHost.runOperator` would hand it a capability lease on the spot,
    /// because it grants one precisely when the impact needs no confirmation.
    @Test(arguments: allOperatorToolIDs)
    func declaredImpactIsNeverBelowItsCapabilityFloor(toolID: String) throws {
        let tool = try #require(OperatorCatalog.spec(for: toolID)?.tool)
        #expect(tool.impact >= CapabilityImpactMapping.minimumImpact(for: tool.capability))
    }

    /// …and the three read operators must not be pushed *above* it either.
    ///
    /// This is the over-gating half, and it is the mistake that would actually be easy to make here:
    /// `CapabilityImpactMapping.defaultImpact(.runPlugin)` is `.externalImpact`, whose
    /// `requiresConfirmation` is `true`. Had the catalog taken its impact from the execute-impact
    /// function, all three read-only operators would require a human confirmation — they would be
    /// escalated to the Approval Inbox instead of running, and `RuntimeHost.runOperator` would skip
    /// the lease grant that a non-confirming run depends on. Research Brief, On-Chain Watch, and
    /// Identity Review are supposed to run in Observe and produce an artifact plus a receipt, so
    /// "does not require confirmation" is the behaviour, not the label.
    @Test(arguments: [
        OperatorCatalog.researchBriefID,
        OperatorCatalog.onChainWatchID,
        OperatorCatalog.identityReviewID
    ])
    func readOperatorsRunWithoutConfirmationAndAreNotCryptoScoped(toolID: String) throws {
        let tool = try #require(OperatorCatalog.spec(for: toolID)?.tool)
        #expect(tool.impact == .readOnly)
        #expect(tool.impact.requiresConfirmation == false)
        #expect(CapabilityImpactMapping.defaultImpact(for: tool.capability).requiresConfirmation)
        #expect(CapabilityDomain.isCrypto(tool.capability) == false)
    }

    /// The prepared action is the one crypto operator, and it is the only one that confirms.
    @Test
    func onlyThePreparedActionIsCryptoScopedAndConfirmFirst() throws {
        let cryptoSpecs = OperatorCatalog.all.filter { CapabilityDomain.isCrypto($0.tool.capability) }
        #expect(cryptoSpecs.map(\.tool.id) == [OperatorCatalog.preparedActionID])

        let prepared = try #require(OperatorCatalog.spec(for: OperatorCatalog.preparedActionID)?.tool)
        #expect(prepared.impact == .highRisk)
        #expect(prepared.impact.requiresConfirmation)
        #expect(prepared.impact == CapabilityImpactMapping.minimumImpact(for: prepared.capability))

        let confirming = OperatorCatalog.all.filter(\.tool.impact.requiresConfirmation)
        #expect(confirming.map(\.tool.id) == [OperatorCatalog.preparedActionID])
    }

    /// Every operator writes an artifact *and* a receipt, so every operator must require both record
    /// shape checks plus context freshness.
    ///
    /// `OperatorCatalog` names these once in a shared constant and its comment claims that means "a
    /// new operator can't be added without them". Nothing enforced that: `requiredCheckIDs` is a
    /// plain array argument, so a new spec can pass any list it likes. This is the enforcement. An
    /// operator missing `artifact.schema` would persist a record whose shape was never validated,
    /// and one missing `receipt.schema` would write the receipt that is the whole audit trail for
    /// the run without checking it.
    @Test(arguments: allOperatorToolIDs)
    func everyOperatorRequiresTheRecordShapeChecksAndAReceipt(toolID: String) throws {
        let tool = try #require(OperatorCatalog.spec(for: toolID)?.tool)
        for required in [
            StandardCheckID.contextFresh,
            RecordSchemaCheckID.artifactSchema,
            RecordSchemaCheckID.receiptSchema
        ] {
            #expect(tool.requiredCheckIDs.contains(required), "\(toolID) does not require \(required)")
        }
        // Explicit, and not inherited from the impact class: `ActionImpactClass.readOnly`
        // `requiresReceipt` is `false`, so the three read operators only produce the receipt that
        // makes a run auditable because the tool definition overrides that default.
        #expect(tool.requiresReceipt)
    }

    /// Any operator touching an address or a chain must have those values checked before it runs,
    /// and the one that declares an `ens` field must have the name format checked.
    ///
    /// Tied to the input schema rather than hardcoded per tool, so an operator that starts accepting
    /// an address cannot be added without the matching check. A declared-but-unchecked `address`
    /// means a malformed or homoglyph value reaches the run; a declared-but-unchecked `ens` is the
    /// specific gap `OperatorCatalog` records closing.
    /// **Keyed on what `toParameters()` can emit, not on what each schema declares.** The earlier
    /// version guarded each assertion behind `if declared.contains("address")`, so for the two
    /// operators that declare neither — research and identity review — all three branches were
    /// skipped and the test passed having asserted nothing. That is the vacuous shape the catalog's
    /// own note describes: the input schemas are `allowsAdditionalFields: true` and
    /// `OperatorRequest.toParameters()` emits `chain`, `address` and `ens` for *any* request
    /// carrying a watchlist, which `RuntimeHost.runResearchBrief(query:watchlist:)` accepts. So
    /// every operator can receive all three, and every operator must check all three.
    @Test(arguments: allOperatorToolIDs)
    func addressChainAndENSFieldsAreAlwaysChecked(toolID: String) throws {
        let tool = try #require(OperatorCatalog.spec(for: toolID)?.tool)
        let required = Set(tool.requiredCheckIDs)
        #expect(required.contains(StandardCheckID.addressFormat))
        #expect(required.contains(StandardCheckID.chainInScope))
        #expect(required.contains(StandardCheckID.ensNameFormat))
    }

    /// `toParameters()` is the reason the test above cannot key on declared fields. Pinned directly,
    /// so the premise is checked rather than restated in a comment.
    @Test
    func anyRequestWithAWatchlistEmitsChainAddressAndENS() {
        let parameters = OperatorRequest(
            query: "treasury",
            watchlist: [WatchTarget(chain: "ethereum", address: "0xabc", ens: "vitalik.eth")]
        ).toParameters()

        #expect(parameters["chain"] != nil)
        #expect(parameters["address"] != nil)
        #expect(parameters["ens"] != nil)
    }

    /// Ids are the join key between three independent tables — the catalog, `ModelTaskKind`, and the
    /// registry — so a duplicate or a drifting task kind is a silent misroute, not a build error.
    @Test
    func toolIDsAreUniqueAndMatchTheirModelTaskKind() {
        let ids = OperatorCatalog.all.map(\.tool.id)
        #expect(Set(ids).count == ids.count)
        for spec in OperatorCatalog.all {
            // The router's table is keyed on task kind; the catalog is keyed on tool id. They are
            // the same string for every operator, which is what lets `spec(for:)` and
            // `TaskKindModelRouter.localFirstDefault` agree about a run without a second mapping.
            #expect(spec.modelTaskKind == spec.tool.id)
        }
        #expect(OperatorCatalog.spec(for: "operator.not.registered") == nil)
    }

    /// `ToolRegistry.register` rejects a definition with `definitionProblems`, and `registerOperators`
    /// reports that as a conflict it cannot distinguish from a real id collision. Catching it here
    /// names the actual cause.
    @Test(arguments: allOperatorToolIDs)
    func toolDefinitionsAreWellFormed(toolID: String) throws {
        let tool = try #require(OperatorCatalog.spec(for: toolID)?.tool)
        #expect(tool.definitionProblems.isEmpty, "\(toolID): \(tool.definitionProblems)")
    }
}

@Suite("Operator registration")
struct OperatorRegistrationTests {
    @Test
    func registeringOperatorsReportsNoConflictsAndIsIdempotent() async {
        let registry = ToolRegistry()

        #expect(await registry.registerOperators().isEmpty)
        #expect(await registry.allTools.count == OperatorCatalog.all.count)
        for spec in OperatorCatalog.all {
            #expect(await registry.tool(id: spec.tool.id) == spec.tool)
        }

        // Re-registering the identical definitions is `alreadyRegistered`, which `succeeded` treats
        // as success. This matters because two `RuntimeHost`s can exist in one process and each
        // bootstraps its own registry — and because a single host's `bootstrap()` must be safe to
        // call on every entry point.
        #expect(await registry.registerOperators().isEmpty)
        #expect(await registry.allTools.count == OperatorCatalog.all.count)
    }

    /// A *different* definition already holding an operator's id is reported rather than silently
    /// overwritten, so bootstrap order cannot quietly change an operator's governance.
    @Test
    func aConflictingPriorDefinitionIsReportedAndDoesNotOverwriteGovernance() async {
        let registry = ToolRegistry()
        // Same id, but read-only and crypto-free where the real one is a high-risk wallet draft:
        // exactly the substitution that must not win.
        let impostor = ToolDefinition(
            id: OperatorCatalog.preparedActionID,
            title: "Prepare On-Chain Action",
            capability: .runPlugin,
            impact: .readOnly,
            requiresReceipt: false
        )
        #expect(await registry.register(impostor) == .registered)

        let conflicts = await registry.registerOperators()
        #expect(conflicts.map(\.id) == [OperatorCatalog.preparedActionID])
        // The impostor is still what is registered — `register` refuses rather than replaces — so a
        // caller that discards the returned conflicts is running with the wrong governance. That is
        // why `registerOperators` returns them at all.
        #expect(await registry.tool(id: OperatorCatalog.preparedActionID) == impostor)
        // Every other operator still registered cleanly.
        #expect(await registry.allTools.count == OperatorCatalog.all.count)
    }
}
