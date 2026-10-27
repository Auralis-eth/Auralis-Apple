import AuralisPrimaryModels
import AuralisFoundation
import Foundation
import OperatorsFeature
import ReceiptsCore
import AuralisRuntime
@testable import RuntimeKit
import Testing

/// In-memory receipt store, newest-first, matching `SwiftDataReceiptStore.latest`.
private actor FailClosedReceiptStore: ReceiptStore {
    private var records: [ReceiptRecord] = []

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        let record = ReceiptRecord(
            id: UUID(), sequenceID: records.count + 1, createdAt: receipt.createdAt,
            actor: receipt.actor, actorDetail: receipt.actorDetail,
            authorityDetail: receipt.authorityDetail, mode: receipt.mode, trigger: receipt.trigger,
            scope: receipt.scope, summary: receipt.summary, provenance: receipt.provenance,
            isSuccess: receipt.isSuccess, correlationID: receipt.correlationID, details: receipt.details
        )
        records.insert(record, at: 0)
        return record
    }

    func latest(limit: Int) async throws -> [ReceiptRecord] { Array(records.prefix(limit)) }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] {
        Array(records.filter { $0.correlationID == correlationID }.prefix(limit))
    }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { records.removeAll() }
}

/// The registration invariants `bootstrap()` enforces, asserted from the outside.
///
/// These are the positive form of three of the violation classes in `performBootstrap()`. They are
/// worth having on their own: the violations themselves are only reachable through the injection
/// seam, so without these a real regression in `PolicyActionCatalog` or `OperatorCatalog` — a tool
/// naming a check that was renamed, a new state-changing tool that forgot `requiresReceipt: true` —
/// would be caught by `failClosed` at launch and by nothing at all in CI.
@MainActor
@Suite("Governed runtime registration invariants")
struct BootstrapRegistrationInvariantTests {
    @Test("the shipping catalog bootstraps with no governance violations")
    func theStandardCatalogBootstrapsCleanly() async {
        let host = RuntimeHost(receiptStore: FailClosedReceiptStore())

        await host.bootstrap()

        #expect(host.bootstrapFailureReason == nil)
        #expect(host.isPaused == false)
        #expect(await host.pauseGate.isPaused() == false)
    }

    /// A tool requiring a check nobody registered means the pipeline cannot prove the call was
    /// checked, which is why it is a launch failure rather than a warning.
    @Test("every registered tool's required checks are registered")
    func everyRequiredCheckIsRegistered() async {
        let host = RuntimeHost(receiptStore: FailClosedReceiptStore())

        for tool in await host.registeredTools() {
            for checkID in tool.requiredCheckIDs {
                let check = await host.checkRegistry.check(id: checkID)
                #expect(check != nil, "\(tool.id) requires unregistered check \(checkID)")
            }
        }
    }

    @Test("every state-changing registered tool demands a receipt")
    func everyStateChangingToolRequiresAReceipt() async {
        let host = RuntimeHost(receiptStore: FailClosedReceiptStore())

        for tool in await host.registeredTools() where tool.impact != .readOnly {
            #expect(tool.requiresReceipt, "state-changing tool \(tool.id) does not require a receipt")
        }
    }

    @Test("tool IDs are unique across the operator and policy catalogs")
    func toolIDsDoNotCollide() async {
        let host = RuntimeHost(receiptStore: FailClosedReceiptStore())

        let ids = await host.registeredTools().map(\.id)

        #expect(Set(ids).count == ids.count)
    }
}

/// The fail-closed response to a governance-integrity failure.
///
/// `failClosed(violations:)` carries more rationale than almost anything else in the package — it is
/// what replaced `precondition`s that were live in release builds, so a registry problem used to
/// crash the app at cold start — and it had no test of any kind. Violations are injected because
/// they are otherwise unreachable from outside the host; see `injectedBootstrapViolations`.
@MainActor
@Suite("Governed runtime fail-closed")
struct BootstrapFailClosedTests {
    private static let violation = "Conflicting policy tool ID: policy.signMessage"

    private func failedHost(
        receiptStore: any ReceiptStore,
        violations: [String] = [violation],
        initialPauseReason: String? = nil
    ) async -> RuntimeHost {
        let host = RuntimeHost(
            receiptStore: receiptStore,
            governance: RuntimeGovernanceOptions(initialPauseReason: initialPauseReason)
        )
        host.injectedBootstrapViolations = violations
        await host.bootstrap()
        return host
    }

    @Test("a governance-integrity violation pauses the runtime and says why")
    func integrityViolationPausesTheRuntime() async {
        let host = await failedHost(receiptStore: FailClosedReceiptStore())

        #expect(host.isPaused)
        #expect(await host.pauseGate.isPaused())
        #expect(host.bootstrapFailureReason == Self.violation)
        // The reason a person reads has to name the specific problem, not only that there was one —
        // the whole argument for pausing instead of crashing is that a diagnostic survives.
        let reason = host.pauseReason ?? ""
        #expect(reason.contains(Self.violation))
        #expect(reason.contains("could not verify its own tool and check registration"))
    }

    /// A runtime that could not verify its own registration must not go on to *create* authority.
    /// `performBootstrap` used to run the bulk seed regardless, so a failed-closed host still minted a
    /// 24-hour standing lease per capability per installed playbook — leaving Mission Control's
    /// active-grants list showing authority nobody requested, issued by the runtime in the same breath
    /// as it refused to vouch for itself. A healthy host seeds as before (covered by
    /// ``StandingAuthorityScopeTests``); this pins the refusal.
    @Test("a host that failed closed seeds no standing authority")
    func failedBootstrapSeedsNoStandingAuthority() async {
        let host = await failedHost(receiptStore: FailClosedReceiptStore())

        #expect(host.bootstrapFailureReason != nil)
        #expect(await host.activeCapabilityLeases().isEmpty)
    }

    @Test("every violation is reported, not only the first")
    func allViolationsAreReported() async {
        let host = await failedHost(
            receiptStore: FailClosedReceiptStore(),
            violations: ["first violation", "second violation", "third violation"]
        )

        let reason = host.bootstrapFailureReason ?? ""
        #expect(reason.contains("first violation"))
        #expect(reason.contains("second violation"))
        #expect(reason.contains("third violation"))
    }

    @Test("governed work is refused after a governance-integrity failure")
    func governedWorkIsRefused() async {
        let host = await failedHost(receiptStore: FailClosedReceiptStore())

        let outcome = await host.runOperator(
            toolID: OperatorCatalog.researchBriefID,
            request: OperatorRequest(query: "should not run")
        )

        guard case .blocked = outcome else {
            Issue.record("Governed work ran on a runtime that could not vouch for its registries: \(outcome)")
            return
        }
    }

    /// Nothing a person does from Mission Control repairs a registration failure — only a relaunch
    /// that registers cleanly does. Without the refusal, the kill switch could lift a pause whose
    /// cause was still present, leaving `bootstrapFailureReason` populated beside a running pipeline.
    @Test("an operator cannot resume a governance-integrity pause")
    func theKillSwitchCannotLiftAnIntegrityPause() async {
        let host = await failedHost(receiptStore: FailClosedReceiptStore())

        await host.setPaused(false)

        #expect(host.isPaused)
        #expect(await host.pauseGate.isPaused())
        #expect(host.pauseReason != nil)
    }

    /// The refusal is announced rather than silent: a resume that does nothing and says nothing is
    /// indistinguishable from a broken button.
    @Test("the refused resume is announced on the event bus")
    func theRefusedResumeIsAnnounced() async {
        let host = await failedHost(receiptStore: FailClosedReceiptStore())

        await host.setPaused(false)

        let updates = await host.recentEvents(limit: 64).compactMap { envelope -> String? in
            guard case let .executionUpdate(message) = envelope.event else { return nil }
            return message
        }
        #expect(updates.contains { $0.contains("Resume refused") })
    }

    /// A pause the *runtime* imposed on itself must not be recorded as a person pressing the kill
    /// switch. The ledger's whole value is that it says who did what, and `humanApproval` by
    /// `.human` would name someone who did nothing.
    @Test("the integrity pause is receipted with its own actor and authority")
    func theIntegrityPauseIsReceiptedAsSuch() async throws {
        let store = FailClosedReceiptStore()
        _ = await failedHost(receiptStore: store)

        let receipts = try await store.latest(limit: 64)
        let pauseReceipt = try #require(receipts.first { $0.trigger == "runtime.paused" })
        #expect(pauseReceipt.details.values["origin"] == .string("governanceIntegrity"))
        #expect(pauseReceipt.details.values["paused"] == .bool(true))
        // The runtime's own bootstrap acted, not a person.
        #expect(pauseReceipt.actorDetail?.kind == ActorKind.workflow.rawValue)
        #expect(pauseReceipt.actorDetail?.identifier == "runtime.bootstrap")
        #expect(pauseReceipt.authorityDetail?.source == "policyDefault")
        // And it is filed under the same key as the kill switch's own session, so the two are
        // retrievable as one workflow.
        #expect(pauseReceipt.correlationID == "runtime.pause")
    }

    /// The regression guard for the de-duplication gap.
    ///
    /// `enqueuePauseFlip` skips a flip to the value already requested, and the record used to be
    /// tied to the flip. `RuntimeHost.persistent(...)` returns a host with `initialPauseReason` set
    /// when storage is unavailable, so `requestedPause` is already `true` before `bootstrap()` runs
    /// — and a governance-integrity failure on top of it was de-duplicated away, writing no receipt
    /// and publishing no event. A host that starts paused writes no pause receipt either, so in the
    /// one configuration where both failures coincide, nothing anywhere recorded that governance
    /// had failed closed.
    @Test("a governance-integrity failure is receipted even when the runtime was already paused")
    func theIntegrityPauseIsReceiptedOnAnAlreadyPausedRuntime() async throws {
        let store = FailClosedReceiptStore()
        let host = await failedHost(
            receiptStore: store,
            initialPauseReason: "Operator runtime storage is unavailable."
        )

        let receipts = try await store.latest(limit: 64)
        let pauseReceipt = try #require(receipts.first { $0.trigger == "runtime.paused" })
        #expect(pauseReceipt.details.values["origin"] == .string("governanceIntegrity"))
        #expect(pauseReceipt.actorDetail?.identifier == "runtime.bootstrap")
        // The stronger cause is the one on screen: an integrity failure outranks a storage outage,
        // and it is the only one `setPaused(false)` refuses to lift.
        #expect(host.pauseReason?.contains("could not verify its own tool and check registration") == true)
        #expect(host.bootstrapFailureReason == Self.violation)
    }

    /// A duplicate *operator* flip must still be de-duplicated. The exemption is scoped to the
    /// governance-integrity origin, and widening it would bring back the duplicate
    /// "Operator activity paused" receipt the guard was added to prevent.
    @Test("a repeated operator pause still writes only one receipt")
    func repeatedOperatorPausesAreStillDeduplicated() async throws {
        let store = FailClosedReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        await host.bootstrap()

        await host.setPaused(true, reason: "First")
        await host.setPaused(true, reason: "Duplicate")

        let receipts = try await store.latest(limit: 64)
        #expect(receipts.filter { $0.trigger == "runtime.paused" }.count == 1)
    }

    /// A host that starts paused for a *storage* reason, with registries that register cleanly, is
    /// left exactly as it was: no integrity receipt, and the kill switch still works.
    @Test("a storage pause with healthy registries stays resumable")
    func aStoragePauseWithoutViolationsIsResumable() async throws {
        let store = FailClosedReceiptStore()
        let host = RuntimeHost(
            receiptStore: store,
            governance: RuntimeGovernanceOptions(
                initialPauseReason: "Operator runtime storage is unavailable."
            )
        )
        await host.bootstrap()

        #expect(host.bootstrapFailureReason == nil)
        let afterBootstrap = try await store.latest(limit: 64)
        #expect(afterBootstrap.contains { $0.trigger == "runtime.paused" } == false)

        await host.setPaused(false)

        #expect(host.isPaused == false)
        #expect(await host.pauseGate.isPaused() == false)
    }
}
