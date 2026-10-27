import AuralisReceipts
import OperatorsFeature
import AuralisRuntime
@testable import RuntimeKit
import Testing

@Suite("Record-shape deterministic checks")
struct RecordSchemaCheckTests {
    private func proposal(_ parameters: [String: String]) -> ActionProposal {
        ActionProposal(
            actor: .human,
            intent: "x",
            capability: .runPlugin,
            impact: .readOnly,
            parameters: parameters
        )
    }

    // MARK: - Receipt schema

    @Test("a blank payload key is refused")
    func blankReceiptPayloadKeyIsRefused() async {
        let check = ReceiptSchemaCheck()

        #expect(await check.evaluate(proposal(["": "orphaned"])).passed == false)
        #expect(await check.evaluate(proposal(["  ": "orphaned"])).passed == false)
    }

    /// Receipts carry no schema version, so there is nothing for a proposal to declare and nothing
    /// to fail closed on. An ordinary parameter set passes cleanly.
    @Test("a well-formed proposal passes with no detail")
    func wellFormedReceiptProposalPasses() async {
        let result = await ReceiptSchemaCheck().evaluate(proposal(["address": "0xabc"]))

        #expect(result.passed)
        #expect(result.detail == nil)
    }

    @Test("an empty proposal passes")
    func emptyReceiptProposalPasses() async {
        let result = await ReceiptSchemaCheck().evaluate(proposal([:]))

        #expect(result.passed)
        #expect(result.detail == nil)
    }

    // MARK: - Artifact schema

    @Test("the version this build writes is accepted")
    func currentArtifactVersionPasses() async {
        let result = await ArtifactSchemaCheck().evaluate(
            proposal([
                RecordSchemaKey.artifactVersion: String(ArtifactSchema.currentVersion),
                RecordSchemaKey.artifactType: ArtifactType.report.rawValue
            ])
        )

        #expect(result.passed)
        #expect(result.detail == nil)
    }

    @Test("an artifact version this build cannot read fails closed")
    func unsupportedArtifactVersionFailsClosed() async {
        let unsupported = (ArtifactSchema.supportedVersions.max() ?? 0) + 1
        let result = await ArtifactSchemaCheck().evaluate(
            proposal([RecordSchemaKey.artifactVersion: String(unsupported)])
        )

        #expect(result.passed == false)
        #expect(result.detail?.contains("is not one this build reads") == true)
    }

    @Test("an unknown artifact type is refused and the known set is named")
    func unknownArtifactTypeIsRefused() async {
        let result = await ArtifactSchemaCheck().evaluate(
            proposal([RecordSchemaKey.artifactType: "spreadsheet"])
        )

        #expect(result.passed == false)
        #expect(result.detail?.contains("spreadsheet") == true)
        #expect(result.detail?.contains(ArtifactType.brief.rawValue) == true)
    }

    @Test("every real artifact type is accepted", arguments: ArtifactType.allCases)
    func everyArtifactTypeIsAccepted(type: ArtifactType) async {
        let result = await ArtifactSchemaCheck().evaluate(
            proposal([RecordSchemaKey.artifactType: type.rawValue])
        )

        #expect(result.passed)
    }

    @Test("a blank title and an oversized body are refused")
    func artifactFieldContractIsEnforced() async {
        let check = ArtifactSchemaCheck()

        #expect(await check.evaluate(proposal(["artifactTitle": "   "])).passed == false)
        #expect(
            await check.evaluate(
                proposal(["artifactContent": String(repeating: "a", count: ArtifactSchema.maximumContentLength + 1)])
            ).passed == false
        )
        // At the limit, not over it.
        #expect(
            await check.evaluate(
                proposal(["artifactContent": String(repeating: "a", count: ArtifactSchema.maximumContentLength)])
            ).passed
        )
    }

    @Test("an undeclared artifact version passes and says so")
    func undeclaredArtifactVersionPassesExplicitly() async {
        let result = await ArtifactSchemaCheck().evaluate(proposal([:]))

        #expect(result.passed)
        #expect(result.detail == "no declared artifact schema version")
    }

    // MARK: - Registration

    @Test("both record-shape checks register and resolve")
    func registrationResolvesBothChecks() async {
        let registry = DeterministicCheckRegistry()
        let conflicts = await registry.registerSchemaChecks()

        #expect(conflicts.isEmpty)
        #expect(await registry.check(id: RecordSchemaCheckID.receiptSchema) != nil)
        #expect(await registry.check(id: RecordSchemaCheckID.artifactSchema) != nil)
    }

    @Test("the three check sets register onto one registry without colliding")
    func allCheckSetsCoexist() async {
        let registry = DeterministicCheckRegistry()

        var conflicts = await registry.registerStandardChecks()
        conflicts += await registry.registerPolicyToolChecks()
        conflicts += await registry.registerSchemaChecks()

        #expect(conflicts.isEmpty)
    }
}

@Suite("Check registry coverage contract")
struct CheckRegistryCoverageTests {
    /// Checks that are deliberately available for a *proposal* to name rather than required by any
    /// tool. Anything not listed here must be required by a production tool, so a check can never
    /// again be registered and then quietly never run.
    private static let proposalLevelCheckIDs: Set<String> = []

    private var productionCheckIDs: Set<String> {
        let toolRequired = (PolicyActionCatalog.tools + OperatorCatalog.all.map(\.tool))
            .flatMap(\.requiredCheckIDs)
        return Set(toolRequired)
    }

    @Test("every registered check is required by a tool or declared proposal-level")
    func noRegisteredCheckIsDead() async {
        let registry = DeterministicCheckRegistry()
        await registry.registerStandardChecks()
        await registry.registerPolicyToolChecks()
        await registry.registerSchemaChecks()

        // Asked of the registry rather than hand-written, so a check that is registered and then
        // required by nothing cannot pass this test by being left off a literal.
        let registered = await registry.registeredCheckIDs

        let dead = registered
            .subtracting(productionCheckIDs)
            .subtracting(Self.proposalLevelCheckIDs)
        #expect(dead.isEmpty, "registered but never required: \(dead.sorted())")
    }

    /// The six checks P0.5-802 requires the registry to contain. Deliberately spelled out rather
    /// than asked of the registry: derived from `registeredCheckIDs` this would assert nothing, and
    /// the point is that deleting one of these six is a test failure, not a silent scope reduction.
    @Test("the registry contains every check the deterministic-check ticket requires")
    func registryContainsRequiredCheckSet() async {
        let registry = DeterministicCheckRegistry()
        await registry.registerStandardChecks()
        await registry.registerPolicyToolChecks()
        await registry.registerSchemaChecks()

        let required: Set<String> = [
            StandardCheckID.addressFormat,
            StandardCheckID.ensNameFormat,
            StandardCheckID.chainInScope,
            StandardCheckID.contextFresh,
            RecordSchemaCheckID.receiptSchema,
            RecordSchemaCheckID.artifactSchema
        ]

        #expect(required.subtracting(await registry.registeredCheckIDs).isEmpty)
    }

    /// The wallet payloads carry addresses under `payload.*`, which `address.format` cannot see, so
    /// checksum verification on the signing path depends entirely on this pairing. Asserted here
    /// because dropping the check ID from a tool is invisible at runtime — the action simply stops
    /// being checksum-verified and still succeeds.
    @Test("every wallet action that carries an address checksum-verifies it")
    func everyAddressCarryingActionVerifiesItsChecksum() {
        let addressCarrying: Set<String> = [
            PolicyActionCatalog.toolID(for: .signMessage),
            PolicyActionCatalog.toolID(for: .approveSpending),
            PolicyActionCatalog.toolID(for: .draftTransaction)
        ]

        for tool in PolicyActionCatalog.tools where addressCarrying.contains(tool.id) {
            #expect(
                tool.requiredCheckIDs.contains(PolicyToolCheckID.addressChecksum),
                "\(tool.id) carries an address but does not verify its checksum"
            )
        }
    }

    @Test("every check a production tool requires is one the host registers")
    func everyRequiredCheckIsRegistered() async {
        let registry = DeterministicCheckRegistry()
        await registry.registerStandardChecks()
        await registry.registerPolicyToolChecks()
        await registry.registerSchemaChecks()

        for id in productionCheckIDs {
            #expect(await registry.check(id: id) != nil, "\(id) is required by a tool but not registered")
        }
    }

    @Test("every operator validates both record shapes it writes")
    func everyOperatorValidatesItsRecords() {
        for spec in OperatorCatalog.all {
            #expect(
                spec.tool.requiredCheckIDs.contains(RecordSchemaCheckID.artifactSchema),
                "\(spec.tool.id) writes an artifact but does not validate its shape"
            )
            #expect(
                spec.tool.requiredCheckIDs.contains(RecordSchemaCheckID.receiptSchema),
                "\(spec.tool.id) writes a receipt but does not validate its shape"
            )
        }
    }

    @Test("the stamp the host applies satisfies the checks that read it")
    func hostStampSatisfiesItsOwnChecks() async {
        let registry = DeterministicCheckRegistry()
        await registry.registerSchemaChecks()
        var parameters = RecordSchemaKey.currentDeclaration
        parameters[RecordSchemaKey.artifactType] = ArtifactType.report.rawValue

        let results = await registry.evaluate(
            ids: [RecordSchemaCheckID.receiptSchema, RecordSchemaCheckID.artifactSchema],
            for: ActionProposal(
                actor: .human,
                intent: "x",
                capability: .runPlugin,
                impact: .readOnly,
                parameters: parameters
            )
        )

        #expect(results.allPassed)
        // And neither reports a problem. The artifact check saw a declared version; the receipt
        // check has none to see, so a clean pass is all it can report.
        #expect(results.allSatisfy { $0.detail == nil })
    }
}
