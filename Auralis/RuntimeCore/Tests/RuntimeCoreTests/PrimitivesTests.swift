import AuralisFoundation
import Foundation
@testable import RuntimeCore
import Testing

@Suite("ApprovalRegistry lifecycle")
struct ApprovalRegistryLifecycleTests {
    @Test
    func consumingApprovalRemovesItFromPendingAgeQueries() async {
        let registeredAt = Date(timeIntervalSince1970: 1_000)
        let proposal = ActionProposal(
            actor: .human,
            intent: "Approve test action",
            capability: .audioPlayback,
            impact: .readOnly
        )
        let request = ApprovalRequest(proposal: proposal, prompt: "Approve?")
        let registry = ApprovalRegistry()

        await registry.register(request, toolID: "test.tool", at: registeredAt)
        #expect(await registry.oldestPendingDate() == registeredAt)

        #expect(await registry.consume(request) == "test.tool")
        #expect(await registry.oldestPendingDate() == nil)
    }

    @Test("latest eligible approval advances without being masked by an older pending request")
    func latestEligibleApprovalUsesTheCutoffAndNewestMatchingRequest() async {
        let proposal = ActionProposal(
            actor: .human,
            intent: "Approve test action",
            capability: .audioPlayback,
            impact: .readOnly
        )
        let oldest = ApprovalRequest(proposal: proposal, prompt: "Approve oldest?")
        let newlyOverdue = ApprovalRequest(proposal: proposal, prompt: "Approve newer?")
        let stillFresh = ApprovalRequest(proposal: proposal, prompt: "Approve fresh?")
        let registry = ApprovalRegistry()

        await registry.register(oldest, toolID: "oldest", at: Date(timeIntervalSince1970: 1_000))
        await registry.register(newlyOverdue, toolID: "newer", at: Date(timeIntervalSince1970: 2_000))
        await registry.register(stillFresh, toolID: "fresh", at: Date(timeIntervalSince1970: 3_000))

        #expect(
            await registry.latestPendingDate(onOrBefore: Date(timeIntervalSince1970: 2_500))
                == Date(timeIntervalSince1970: 2_000)
        )
    }
}

@Suite("DeterministicCheckRegistry")
struct DeterministicCheckRegistryTests {
    private func proposal() -> ActionProposal {
        ActionProposal(actor: .human, intent: "x", capability: .audioPlayback, impact: .readOnly)
    }

    @Test
    func evaluatesRegisteredChecksInOrder() async {
        let registry = DeterministicCheckRegistry()
        await registry.register(ClosureCheck(id: "a") { _ in .init(checkID: "a", passed: true) })
        await registry.register(ClosureCheck(id: "b") { _ in .init(checkID: "b", passed: false) })

        let results = await registry.evaluate(ids: ["a", "b"], for: proposal())

        #expect(results.map(\.checkID) == ["a", "b"])
        #expect(results.allPassed == false)
        #expect(results.firstFailure?.checkID == "b")
    }

    @Test
    func unknownCheckFailsClosed() async {
        let registry = DeterministicCheckRegistry()
        let results = await registry.evaluate(ids: ["missing"], for: proposal())
        #expect(results.first?.passed == false)
        #expect(results.first?.detail == "unregistered check")
    }

    @Test("a duplicate ID is reported and keeps the incumbent check")
    func duplicateIDIsReportedAndKeepsIncumbent() async {
        let registry = DeterministicCheckRegistry()

        let first = await registry.register(ClosureCheck(id: "a") { _ in .init(checkID: "a", passed: false) })
        #expect(first == .registered)

        // Same ID, opposite verdict. Last-writer-wins would silently swap a failing governance check
        // for a passing one while every tool that required "a" kept reporting a pass.
        let second = await registry.register(ClosureCheck(id: "a") { _ in .init(checkID: "a", passed: true) })
        #expect(second == .conflict(id: "a"))
        #expect(second.succeeded == false)

        let results = await registry.evaluate(ids: ["a"], for: proposal())
        #expect(results.first?.passed == false)
    }

    @Test("an empty check list vacuously passes and has no failure")
    func emptyResultsVacuouslyPass() async {
        let registry = DeterministicCheckRegistry()
        let results = await registry.evaluate(ids: [], for: proposal())

        #expect(results.isEmpty)
        #expect(results.allPassed)
        #expect(results.firstFailure == nil)
    }
}

@Suite("ContextBundleContract")
struct ContextBundleContractTests {
    @Test
    func satisfiedWhenFreshAllowedFieldPresent() {
        let now = Date()
        let bundle = ContextBundle(fields: [
            ContextField(key: "address", stringValue: "0xabc", dataClass: .publicIdentifier, source: .chainProvider, lastRefreshed: now)
        ])
        let contract = ContextBundleContract(requirements: [
            ContextFieldRequirement(key: "address", allowedDataClasses: [.publicIdentifier], maxAge: 60, authoritativeSource: .chainProvider, missingFieldBehavior: .fail)
        ])

        let result = contract.validate(bundle, now: now)
        #expect(result.isSatisfied)
        #expect(result.violations.isEmpty)
    }

    @Test
    func flagsMissingDisallowedAndStaleFields() {
        let now = Date()
        let bundle = ContextBundle(fields: [
            ContextField(key: "secret", sensitiveReference: "vault:test", source: .localCache, lastRefreshed: now.addingTimeInterval(-3600))
        ])
        let contract = ContextBundleContract(requirements: [
            ContextFieldRequirement(key: "address", allowedDataClasses: [.publicIdentifier], maxAge: 3_600, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail),
            ContextFieldRequirement(key: "secret", allowedDataClasses: [.publicIdentifier], maxAge: 60, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail)
        ])

        let result = contract.validate(bundle, now: now)
        #expect(result.isSatisfied == false)
        // Missing address plus the secret's wrong class, source, and freshness.
        #expect(result.violations.count == 4)
    }

    @Test
    func rejectsUndeclaredFieldsByDefault() {
        let contract = ContextBundleContract(requirements: [
            ContextFieldRequirement(key: "wallet", allowedDataClasses: [.publicIdentifier], maxAge: 3_600, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail)
        ])
        let result = contract.validate(ContextBundle(fields: [
            ContextField(key: "wallet", stringValue: "0xabc", dataClass: .publicIdentifier),
            ContextField(key: "token", stringValue: "secret", dataClass: .sensitive)
        ]))

        #expect(result.isSatisfied == false)
        #expect(result.violations.contains { $0.contains("undeclared field") })
        #expect(result.approvedBundle.field("token") == nil)
    }

    @Test
    func duplicateKeysCannotValidateOneValueAndDeliverAnother() {
        let contract = ContextBundleContract(requirements: [
            ContextFieldRequirement(
                key: "wallet",
                allowedDataClasses: [.publicIdentifier],
                maxAge: 3_600,
                authoritativeSource: .walletStore,
                missingFieldBehavior: .fail
            )
        ])
        let result = contract.validate(ContextBundle(fields: [
            ContextField(key: "wallet", stringValue: "trusted", dataClass: .publicIdentifier, source: .walletStore),
            ContextField(key: "wallet", stringValue: "injected", dataClass: .sensitive, source: .localCache)
        ]))

        #expect(result.isSatisfied == false)
        #expect(result.violations.contains { $0.contains("duplicate field") })
        #expect(result.approvedBundle.fields.isEmpty)
    }

    @Test
    func omitsUndeclaredAndStaleFieldsFromApprovedProjection() {
        let now = Date()
        let contract = ContextBundleContract(
            requirements: [
                ContextFieldRequirement(key: "wallet", allowedDataClasses: [.publicIdentifier], maxAge: 3_600, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail),
                ContextFieldRequirement(
                    key: "price",
                    allowedDataClasses: [.derived],
                    maxAge: 60,
                    authoritativeSource: .runtimeHost,
                    missingFieldBehavior: .proceedWithoutField
                )
            ],
            additionalFieldBehavior: .omit
        )
        let result = contract.validate(ContextBundle(fields: [
            ContextField(key: "wallet", stringValue: "0xabc", dataClass: .publicIdentifier, source: .runtimeHost, lastRefreshed: now),
            ContextField(key: "price", stringValue: "1", dataClass: .derived, source: .runtimeHost, lastRefreshed: now.addingTimeInterval(-120)),
            ContextField(key: "plugin.payload", stringValue: "ignore", dataClass: .sensitive)
        ]), now: now)

        #expect(result.isSatisfied)
        #expect(result.approvedBundle.field("wallet")?.stringValue == "0xabc")
    }

    @Test
    func rejectsUnreasonableFutureTimestamp() {
        let now = Date()
        let contract = ContextBundleContract(
            requirements: [
                ContextFieldRequirement(key: "price", allowedDataClasses: [.derived], maxAge: 60, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail)
            ],
            maximumFutureSkew: 5
        )
        let result = contract.validate(ContextBundle(fields: [
            ContextField(key: "price", stringValue: "1", dataClass: .derived, source: .runtimeHost, lastRefreshed: now.addingTimeInterval(60))
        ]), now: now)

        #expect(result.isSatisfied == false)
        #expect(result.violations.contains { $0.contains("future refresh timestamp") })
    }

    @Test
    func contractAndBundleRoundTripThroughCodable() throws {
        let contract = ContextBundleContract(
            identifier: "test.wallet",
            requirements: [
                ContextFieldRequirement(key: "wallet", allowedDataClasses: [.publicIdentifier], maxAge: 3_600, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail)
            ]
        )
        let encoded = try JSONEncoder().encode(contract)
        let decoded = try JSONDecoder().decode(ContextBundleContract.self, from: encoded)

        #expect(decoded == contract)
    }

    @Test
    func legacyContractWithoutGovernanceDeclarationsFailsClosed() throws {
        let legacy = #"{"requirements":[{"key":"wallet","isRequired":true,"allowedDataClasses":["publicIdentifier"]}],"missingFieldBehavior":"fail"}"#
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ContextBundleContract.self, from: Data(legacy.utf8))
        }
    }

    @Test
    func rejectsUnknownContractAndBundleSchemaVersions() {
        let contract = ContextBundleContract(schemaVersion: 3, requirements: [])
        let result = contract.validate(ContextBundle(schemaVersion: 3, fields: []))

        #expect(result.isSatisfied == false)
        #expect(result.violations.count == 2)
    }

    @Test
    func rawSensitiveStringIsRedactedAtConstruction() {
        let field = ContextField(
            key: "wallet.seedPhrase",
            stringValue: "never-store-this",
            dataClass: .sensitive,
            source: .walletStore
        )

        #expect(field.value == .redacted)
        #expect(field.stringValue == nil)
        #expect(ContextBundle(fields: [field]).field("secret")?.stringValue == nil)
    }

    @Test
    func governanceBoundaryPreservesMetadataAndProducesValueFreeEvidence() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let contract = ContextBundleContract(
            identifier: "wallet.read",
            requirements: [
                ContextFieldRequirement(
                    key: "wallet",
                    allowedDataClasses: [.publicIdentifier],
                    maxAge: 3_600,
                    authoritativeSource: .walletStore,
                    missingFieldBehavior: .fail
                )
            ]
        )
        let bundle = ContextBundle(fields: [
            ContextField(
                key: "wallet",
                stringValue: "0xprivate-test-value",
                dataClass: .publicIdentifier,
                source: .walletStore,
                lastRefreshed: now
            )
        ])

        let governed = try ContextGovernanceBoundary()
            .authorize(bundle, against: contract, at: now)
            .get()

        #expect(governed.contractIdentifier == "wallet.read")
        #expect(governed.bundle.fields.first?.source == .walletStore)
        #expect(governed.field("wallet")?.stringValue == "0xprivate-test-value")
        #expect(governed.auditSummary.contains("0xprivate-test-value") == false)
    }

    @Test
    func evidenceDigestBindsValuesWithoutDisclosingThem() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let first = ContextBundle(fields: [
            ContextField(key: "wallet", stringValue: "0xfirst", dataClass: .publicIdentifier, source: .walletStore, lastRefreshed: timestamp),
            ContextField(key: "chain", stringValue: "ethereum", dataClass: .publicIdentifier, source: .chainProvider, lastRefreshed: timestamp)
        ])
        let reordered = ContextBundle(fields: Array(first.fields.reversed()))
        let changed = ContextBundle(fields: [
            ContextField(key: "wallet", stringValue: "0xsecond", dataClass: .publicIdentifier, source: .walletStore, lastRefreshed: timestamp),
            first.fields[1]
        ])

        #expect(first.evidenceDigest() == reordered.evidenceDigest())
        #expect(first.evidenceDigest() != changed.evidenceDigest())
        #expect(first.evidenceDigest().contains("0xfirst") == false)
    }

    @Test
    func modelInferenceRequestRefusesUnapprovedContext() {
        #expect(throws: ContextGovernanceFailure.self) {
            _ = try ModelInferenceRequest.authorizing(
                taskKind: ModelTaskKind.operatorResearchBrief,
                bundle: ContextBundle(fields: []),
                contract: ContextBundleContract(requirements: [
                    ContextFieldRequirement(key: "wallet", allowedDataClasses: [.publicIdentifier], maxAge: 3_600, authoritativeSource: .runtimeHost, missingFieldBehavior: .fail)
                ])
            ) { _ in "hi" }
        }
    }

    @Test
    func decodedBundleRemainsUntrustedUntilRevalidated() throws {
        let encoded = try JSONEncoder().encode(ContextBundle(fields: [
            ContextField(
                key: "wallet",
                stringValue: "0xabc",
                dataClass: .publicIdentifier,
                source: .localCache,
                lastRefreshed: .now
            )
        ]))
        let decoded = try JSONDecoder().decode(ContextBundle.self, from: encoded)

        #expect(throws: ContextGovernanceFailure.self) {
            _ = try ModelInferenceRequest.authorizing(
                taskKind: ModelTaskKind.operatorResearchBrief,
                bundle: decoded,
                contract: ContextBundleContract(requirements: [
                    ContextFieldRequirement(
                        key: "wallet",
                        allowedDataClasses: [.publicIdentifier],
                        maxAge: 3_600,
                        authoritativeSource: .walletStore,
                        missingFieldBehavior: .fail
                    )
                ])
            ) { _ in "hi" }
        }
    }

    @Test
    func inferencePromptIsBuiltOnlyFromTheApprovedProjection() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let request = try ModelInferenceRequest.authorizing(
            taskKind: ModelTaskKind.searchAssistant,
            bundle: ContextBundle(fields: [
                ContextField(key: "query", stringValue: "approved", dataClass: .userProvided, source: .userProvided, lastRefreshed: now),
                ContextField(key: "undeclared", stringValue: "must-not-appear", dataClass: .derived, source: .localCache, lastRefreshed: now)
            ]),
            contract: ContextBundleContract(
                requirements: [
                    ContextFieldRequirement(key: "query", allowedDataClasses: [.userProvided], maxAge: 60, authoritativeSource: .userProvided, missingFieldBehavior: .fail)
                ],
                additionalFieldBehavior: .omit
            ),
            validationDate: now
        ) { context in
            "query=\(context.field("query")?.stringValue ?? ""); extra=\(context.field("undeclared")?.stringValue ?? "none")"
        }

        #expect(request.prompt == "query=approved; extra=none")
        #expect(request.context.bundle.field("undeclared") == nil)
    }

    @Test
    func rejectsBlobLikeBundlesBeforeContextIsAuthorized() {
        let now = Date()
        let oversizedValue = String(repeating: "x", count: ContextBundle.maximumValueByteCount + 1)
        let bundle = ContextBundle(fields: [
            ContextField(key: "payload", stringValue: oversizedValue, dataClass: .userProvided, source: .userProvided, lastRefreshed: now)
        ])
        let contract = ContextBundleContract(requirements: [
            ContextFieldRequirement(key: "payload", allowedDataClasses: [.userProvided], maxAge: 60, authoritativeSource: .userProvided, missingFieldBehavior: .fail)
        ])

        let result = contract.validate(bundle, now: now)

        #expect(result.isSatisfied == false)
        #expect(result.violations.contains { $0.contains("value bytes") })
    }

    @Test
    func rejectsExcessiveFieldCountsAndKeyLengths() {
        let longKey = String(repeating: "k", count: ContextBundle.maximumKeyByteCount + 1)
        let fields = (0...ContextBundle.maximumFieldCount).map { index in
            ContextField(key: index == 0 ? longKey : "field.\(index)", stringValue: "v", dataClass: .derived)
        }

        let violations = ContextBundle(fields: fields).sizeViolations()

        #expect(violations.contains { $0.contains("more than") })
        #expect(violations.contains { $0.contains("field key exceeds") })
    }
}

@Suite("CapabilityLease")
struct CapabilityLeaseTests {
    @Test
    func leaseIsActiveOnlyWithinWindow() {
        let start = Date()
        let lease = CapabilityLease(
            capability: .playbackQueue,
            grantedTo: .system,
            grantedAt: start,
            expiresAt: start.addingTimeInterval(1200)
        )
        #expect(lease.isActive(at: start.addingTimeInterval(600)))
        #expect(lease.isActive(at: start.addingTimeInterval(1200)) == false)
        #expect(lease.isActive(at: start.addingTimeInterval(-1)) == false)
    }

    @Test
    func leaseCarriesReasonAndScope() {
        let start = Date()
        let explicit = CapabilityLease(
            capability: .musicExport,
            reason: "Export a reviewed playlist artifact.",
            scope: .artifact,
            grantedTo: .system,
            grantedAt: start,
            expiresAt: start.addingTimeInterval(1200)
        )
        let defaulted = CapabilityLease(
            capability: .signMessage,
            grantedTo: .system,
            grantedAt: start,
            expiresAt: start.addingTimeInterval(1200)
        )

        #expect(explicit.reason == "Export a reviewed playlist artifact.")
        #expect(explicit.scope == .artifact)
        #expect(defaulted.scope == .account)
        #expect(defaulted.reason.contains("wallet signature"))
    }

    @Test
    func scopedLeaseGrantsOnlyMatchingActorAndSession() async {
        let start = Date()
        let registry = CapabilityLeaseRegistry()
        let planner = ActorRef(kind: .workflow, identifier: "planner")
        let otherPlanner = ActorRef(kind: .workflow, identifier: "other-planner")
        await registry.grant(
            CapabilityLease(
                capability: .playbackQueue,
                grantedTo: planner,
                sessionCorrelationID: "session-1",
                grantedAt: start,
                expiresAt: start.addingTimeInterval(1200)
            )
        )

        #expect(await registry.isGranted(.playbackQueue, to: planner, correlationID: "session-1", at: start.addingTimeInterval(1)))
        #expect(await registry.isGranted(.playbackQueue, to: otherPlanner, correlationID: "session-1", at: start.addingTimeInterval(1)) == false)
        #expect(await registry.isGranted(.playbackQueue, to: planner, correlationID: "session-2", at: start.addingTimeInterval(1)) == false)
    }

    @Test
    func revokedLeaseIsNotGranted() async {
        let start = Date()
        let registry = CapabilityLeaseRegistry()
        let lease = await registry.grant(
            CapabilityLease(capability: .playbackQueue, grantedTo: .system, grantedAt: start, expiresAt: start.addingTimeInterval(1200))
        )
        #expect(await registry.isGranted(.playbackQueue, to: .system, at: start.addingTimeInterval(1)))

        await registry.revoke(id: lease.id, at: start.addingTimeInterval(2))
        #expect(await registry.isGranted(.playbackQueue, to: .system, at: start.addingTimeInterval(3)) == false)
    }

    @Test
    func expiredLeasesAreReportedOnce() async {
        let start = Date()
        let registry = CapabilityLeaseRegistry()
        await registry.grant(
            CapabilityLease(capability: .playbackQueue, grantedTo: .system, grantedAt: start, expiresAt: start.addingTimeInterval(10))
        )

        #expect(await registry.expiredLeases(at: start.addingTimeInterval(11)).map(\.capability) == [.playbackQueue])
        #expect(await registry.expiredLeases(at: start.addingTimeInterval(12)).isEmpty)
    }

    @Test
    func registryHydratesPersistedLeasesAndRestrictions() async {
        let start = Date()
        let store = InMemoryCapabilityLeaseStore()
        let actor = ActorRef(kind: .workflow, identifier: "planner")
        await store.upsert(
            CapabilityLease(
                capability: .playbackQueue,
                grantedTo: actor,
                sessionCorrelationID: "session-1",
                grantedAt: start,
                expiresAt: start.addingTimeInterval(1200)
            )
        )
        await store.upsert(
            CapabilityRestriction(
                kind: .walletAccess,
                reason: "Planning may inspect local context only.",
                appliesTo: actor,
                sessionCorrelationID: "session-1",
                createdAt: start
            )
        )

        let registry = CapabilityLeaseRegistry(store: store)

        #expect(await registry.isGranted(.playbackQueue, to: actor, correlationID: "session-1", at: start.addingTimeInterval(1)))
        #expect(await registry.isDenied(.signMessage, to: actor, correlationID: "session-1", at: start.addingTimeInterval(1)))
    }
}

@Suite("AgentSession")
struct AgentSessionTests {
    @Test
    func accumulatesAndEnds() {
        var session = AgentSession(correlationID: "c1", goal: "organize library", actor: .system)
        session.note(capability: .autoOrganization)
        session.note(capability: .autoOrganization) // dedup
        session.note(model: "on-device", cost: 0)
        session.note(model: "on-device", cost: 0) // dedup name, cost still adds
        let receipt = UUID()
        session.note(receiptID: receipt)

        #expect(session.capabilities == [.autoOrganization])
        #expect(session.modelsUsed == ["on-device"])
        #expect(session.receiptIDs == [receipt])
        #expect(session.isActive)

        session.end()
        #expect(session.isActive == false)
    }

    @Test
    func modelHopsCountInvocationsNotDistinctModels() {
        // A hop is a model *invocation*; the same model called repeatedly is one model, many hops.
        var session = AgentSession(correlationID: "c1", goal: "chain", actor: .system)
        session.note(model: "on-device", cost: 0)
        session.note(model: "on-device", cost: 0)
        session.note(model: "remote", cost: 0)
        #expect(session.modelsUsed == ["on-device", "remote"])
        #expect(session.modelHops == 3)
    }

    @Test
    func telemetryNoteCountsAsHop() {
        var session = AgentSession(correlationID: "c1", goal: "chain", actor: .system)
        let route = ModelRoute(id: "afm", provider: "apple", modelClass: "foundation", locality: .local)
        session.note(telemetry: InferenceTelemetry(route: route, promptTokens: 4, completionTokens: 2, durationSeconds: 0.1, estimatedCost: 0))
        #expect(session.modelHops == 1)
        #expect(session.totalTokens == 6)
    }

    @Test
    func nonInferenceTelemetryDoesNotCountAsHop() {
        // A deterministic local data read carries a route for provenance but is not a model
        // invocation, so it must not inflate the hop count or the models-used list. (P1-AI-103)
        var session = AgentSession(correlationID: "c1", goal: "chain", actor: .system)
        let route = ModelRoute(id: "ledger", provider: "Local ledger", modelClass: "on-device-indexer", locality: .local)
        session.note(telemetry: InferenceTelemetry(
            route: route,
            promptTokens: 0,
            completionTokens: 0,
            durationSeconds: 0.4,
            estimatedCost: 0,
            usesInference: false
        ))
        #expect(session.modelHops == 0)
        #expect(session.modelsUsed.isEmpty)
    }

    @Test
    func usesInferenceSurvivesOutputFieldsRoundTrip() {
        let route = ModelRoute(id: "ledger", provider: "Local ledger", modelClass: "on-device-indexer", locality: .local)
        let dataRead = InferenceTelemetry(route: route, promptTokens: 0, completionTokens: 0, durationSeconds: 0, estimatedCost: 0, usesInference: false)
        #expect(InferenceTelemetry(outputFields: dataRead.outputFields)?.usesInference == false)
        // Legacy fields without the flag decode as inference for backward compatibility.
        var legacyFields = dataRead.outputFields
        legacyFields["usesInference"] = nil
        #expect(InferenceTelemetry(outputFields: legacyFields)?.usesInference == true)
    }

    @Test
    func legacySessionWithoutModelHopsDecodesAsZero() throws {
        // Sessions persisted before `modelHops` existed must still load (they are stored as JSON
        // blobs), decoding as zero hops rather than dropping the whole session.
        let legacy = #"""
        {"id":"00000000-0000-0000-0000-000000000001","correlationID":"c1","goal":"g","goals":[],"startedAt":0,"status":"active","capabilities":[],"receiptIDs":[],"approvalIDs":[],"artifactIDs":[],"modelsUsed":["on-device"],"promptTokens":5,"completionTokens":3,"estimatedCost":0,"memoryTouched":[],"executionUpdates":[]}
        """#
        let session = try JSONDecoder().decode(AgentSession.self, from: Data(legacy.utf8))
        #expect(session.modelHops == 0)
        #expect(session.modelsUsed == ["on-device"])
        #expect(session.promptTokens == 5)
    }
}

@Suite("ModelRouting")
struct ModelRoutingTests {
    @Test
    func staticRouterReturnsRouteAndProvenance() async {
        let route = ModelRoute(id: "afm", provider: "apple", modelClass: "foundation", locality: .local)
        let router = StaticModelRouter(route: route)
        let resolved = await router.route(forTaskKind: "plan")
        #expect(resolved == route)
        #expect(resolved?.provenance.locality == .local)
        #expect(resolved?.provenance.provider == "apple")
    }

    @Test
    func telemetryTotalsTokens() {
        let route = ModelRoute(id: "afm", provider: "apple", modelClass: "foundation", locality: .local)
        let telemetry = InferenceTelemetry(route: route, promptTokens: 10, completionTokens: 5, durationSeconds: 0.2, estimatedCost: 0)
        #expect(telemetry.totalTokens == 15)
    }

    @Test
    func localRouteCostsNothing() {
        let route = ModelRoute(id: "afm", provider: "apple", modelClass: "foundation", locality: .local)
        #expect(route.estimatedCost(promptTokens: 1_000_000, completionTokens: 1_000_000) == 0)
    }

    @Test
    func remoteRouteBillsDeclaredRates() {
        let route = ModelRoute(
            id: "cloud",
            provider: "provider",
            modelClass: "cloud-lm",
            locality: .remote,
            promptCostPerMillionTokens: 3,
            completionCostPerMillionTokens: 15
        )
        // 500k prompt @ $3/M = $1.50 ; 200k completion @ $15/M = $3.00
        #expect(route.estimatedCost(promptTokens: 500_000, completionTokens: 200_000) == 4.5)
    }

    @Test
    func pricingDecodesAsFreeForLegacyRoutes() throws {
        let legacy = #"{"id":"afm","provider":"apple","modelClass":"foundation","locality":"local"}"#
        let route = try JSONDecoder().decode(ModelRoute.self, from: Data(legacy.utf8))
        #expect(route.promptCostPerMillionTokens == 0)
        #expect(route.completionCostPerMillionTokens == 0)
    }

    @Test
    func localityDerivesPrivacyImpact() {
        #expect(InferenceLocality.local.privacyImpact == "On-device — inputs stay on this device")
        #expect(InferenceLocality.remote.privacyImpact == "Sent to provider — inputs leave this device")
        #expect(InferenceLocality.local.privacyImpactShort == "On-device")
        #expect(InferenceLocality.remote.privacyImpactShort == "Off-device")

        let route = ModelRoute(id: "cloud", provider: "p", modelClass: "c", locality: .remote)
        #expect(route.privacyImpact == InferenceLocality.remote.privacyImpact)
        #expect(route.provenance.privacyImpact == InferenceLocality.remote.privacyImpact)
    }
}

@Suite("TaskKindModelRouter")
struct TaskKindModelRouterTests {
    private let onDevice = ModelRoute(id: "afm", provider: "Apple Foundation Models", modelClass: "local-language-model", locality: .local)
    private let cloud = ModelRoute(id: "cloud", provider: "Example Cloud", modelClass: "cloud-lm", locality: .remote, promptCostPerMillionTokens: 3, completionCostPerMillionTokens: 15)

    @Test
    func exactTaskKindWins() async {
        let router = TaskKindModelRouter(routes: ["plan": cloud], defaultRoute: onDevice)
        #expect(await router.route(forTaskKind: "plan") == cloud)
    }

    @Test
    func unmatchedTaskKindFallsBackToDefault() async {
        let router = TaskKindModelRouter(routes: ["plan": cloud], defaultRoute: onDevice)
        #expect(await router.route(forTaskKind: "summarize") == onDevice)
    }

    @Test
    func fallbackRouterIsConsultedBeforeDefault() async {
        // The future-provider hook: a downstream router resolves a kind this one doesn't declare,
        // and it takes precedence over the local default.
        let downstream = StaticModelRouter(route: cloud)
        let router = TaskKindModelRouter(routes: [:], defaultRoute: onDevice, fallback: downstream)
        #expect(await router.route(forTaskKind: "anything") == cloud)
    }

    @Test
    func nothingConfiguredReturnsNil() async {
        let router = TaskKindModelRouter()
        #expect(await router.route(forTaskKind: "plan") == nil)
    }

    @Test
    func routingBuilderAddsEntryWithoutMutatingProviders() async {
        // Providers stay data: a table is extended by value, never by branching at call sites.
        let base = TaskKindModelRouter(defaultRoute: onDevice)
        let extended = base.routing("plan", to: cloud)
        #expect(await extended.route(forTaskKind: "plan") == cloud)
        #expect(await extended.route(forTaskKind: "other") == onDevice)
        // Original is untouched.
        #expect(await base.route(forTaskKind: "plan") == onDevice)
    }
}

@Suite("ModelProviderRegistry")
struct ModelProviderRegistryTests {
    private let cloud = ModelRoute(id: "cloud", provider: "Example Cloud", modelClass: "cloud-lm", locality: .remote, promptCostPerMillionTokens: 3, completionCostPerMillionTokens: 15)

    /// A stub client that echoes which route it was asked to run, so dispatch can be asserted.
    private struct StubClient: ModelInferring {
        let tag: String
        func respond(to request: ModelInferenceRequest, using route: ModelRoute) async throws -> ModelInferenceResponse {
            ModelInferenceResponse(
                content: tag,
                telemetry: InferenceTelemetry(route: route, promptTokens: 0, completionTokens: 0, durationSeconds: 0, estimatedCost: 0)
            )
        }
    }

    @Test
    func emptyRegistryIsLocalFirst() async {
        // With no provider registered the router behaves exactly like the local-first default.
        let router = ModelProviderRegistry().makeRouter()
        let resolved = await router.route(forTaskKind: ModelTaskKind.autopilotStep)
        #expect(resolved == DefaultModelRoutes.localLanguageModel)
        let unknown = await router.route(forTaskKind: "unregistered.kind")
        #expect(unknown == DefaultModelRoutes.localLanguageModel) // default floor
    }

    @Test
    func registeredProviderOverridesLocalForItsTaskKinds() async {
        var registry = ModelProviderRegistry()
        registry.register(
            ModelProviderRegistry.Provider(
                id: "acme.api",
                routes: [ModelTaskKind.operatorResearchBrief: cloud],
                client: StubClient(tag: "acme")
            )
        )
        let router = registry.makeRouter()
        // Claimed task kind routes to the provider…
        #expect(await router.route(forTaskKind: ModelTaskKind.operatorResearchBrief) == cloud)
        // …everything else stays local.
        #expect(await router.route(forTaskKind: ModelTaskKind.autopilotStep) == DefaultModelRoutes.localLanguageModel)
    }

    @Test
    func inferenceClientDispatchesToRegisteredProviderAndFailsClosedOtherwise() async throws {
        var registry = ModelProviderRegistry()
        registry.register(
            ModelProviderRegistry.Provider(
                id: "acme.api",
                routes: [ModelTaskKind.operatorResearchBrief: cloud],
                client: StubClient(tag: "acme")
            )
        )
        let client = registry.makeInferenceClient()
        let request = try ModelInferenceRequest.authorizing(
            taskKind: ModelTaskKind.operatorResearchBrief,
            bundle: ContextBundle(fields: []),
            contract: .noContext(identifier: "test.model.inference")
        ) { _ in "hi" }

        // A registered route dispatches to its provider's client.
        let response = try await client.respond(to: request, using: cloud)
        #expect(response.content == "acme")

        // An unregistered route fails closed rather than silently succeeding.
        let orphan = ModelRoute(id: "orphan", provider: "nobody", modelClass: "x", locality: .remote)
        await #expect(throws: ModelInferenceError.self) {
            _ = try await client.respond(to: request, using: orphan)
        }
    }
}

@Suite("CapabilityImpactMapping")
struct CapabilityImpactMappingTests {
    @Test(arguments: [
        (CapabilityID.signMessage, ActionImpactClass.highRisk),
        (CapabilityID.approveSpending, .highRisk),
        (CapabilityID.draftTransaction, .highRisk),
        (CapabilityID.runPlugin, .externalImpact),
        (CapabilityID.musicExport, .externalImpact),
        (CapabilityID.playlistManagement, .reversibleWrite),
        (CapabilityID.autoOrganization, .reversibleWrite),
        (CapabilityID.audioPlayback, .readOnly)
    ])
    func mapsCapabilityToImpact(_ testCase: (capability: CapabilityID, impact: ActionImpactClass)) {
        #expect(CapabilityImpactMapping.defaultImpact(for: testCase.capability) == testCase.impact)
    }

    @Test
    func coversEveryCapability() {
        for capability in CapabilityID.allCases {
            _ = CapabilityImpactMapping.defaultImpact(for: capability)
        }
    }
}

@Suite("CapabilityDomain")
struct CapabilityDomainTests {
    @Test
    func walletCapabilitiesAreCrypto() {
        #expect(CapabilityDomain.isCrypto(.signMessage))
        #expect(CapabilityDomain.isCrypto(.approveSpending))
        #expect(CapabilityDomain.isCrypto(.draftTransaction))
    }

    @Test
    func nonWalletCapabilitiesAreNotCrypto() {
        #expect(CapabilityDomain.isCrypto(.playlistManagement) == false)
        #expect(CapabilityDomain.isCrypto(.audioPlayback) == false)
        #expect(CapabilityDomain.isCrypto(.musicExport) == false)
        #expect(CapabilityDomain.isCrypto(.runPlugin) == false)
    }
}

@Suite("ActorRef")
struct ActorRefTests {
    @Test
    func roundTripsThroughJSON() throws {
        let actor = ActorRef.model(identifier: "afm", inference: .local(modelClass: "foundation"))
        let data = try JSONEncoder().encode(actor)
        let decoded = try JSONDecoder().decode(ActorRef.self, from: data)
        #expect(decoded == actor)
        #expect(decoded.inference?.locality == .local)
    }
}
