import AuralisPrimaryModels
import AuralisFoundation
import Foundation
@testable import MissionControlFeature
import AuralisRuntime
import AuralisPolicy
import AuralisReceipts
import RuntimeKit
import SnapshotTesting
import SwiftUI
import XCTest

#if canImport(UIKit)
import UIKit
private typealias HostController = UIHostingController<AnyView>
#elseif canImport(AppKit)
import AppKit
private typealias HostController = NSHostingController<AnyView>
#endif

/// Image-snapshot baselines for Mission Control sections.
///
/// Two families of baselines:
///  1. *Empty/initial* state — the model is constructed but `loadConsole()` is not called, so every
///     section shows its static empty copy (`test<Section>`).
///  2. *Populated* state — the model is seeded with deterministic fixtures via `seedForSnapshot(...)`
///     and a fixed `referenceDate`, so date-bearing sections render stable content
///     (`test<Section>Populated`). The injectable `referenceDate` replaces the wall clock that
///     previously made relative/freshness rendering non-deterministic.
///
/// Record baselines with:  `SNAPSHOT_TESTING_RECORD=all swift test`  (Xcode-beta DEVELOPER_DIR).
/// Verify with:            `swift test`.
final class MissionControlSnapshotTests: XCTestCase {
    /// iPhone 16 Pro logical points — a representative portrait canvas.
    private static let canvas = CGSize(width: 402, height: 874)

    /// A fixed instant for populated fixtures (2023-11-14 22:13:20 UTC) and the reference "now" four
    /// hours later, so relative rendering ("in 20 minutes") is stable.
    private static let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
    private static let referenceDate = baseDate.addingTimeInterval(4 * 3600)

    @MainActor
    private func makeModel() -> MissionControlHomeModel {
        let host = RuntimeHost(receiptStore: EmptyReceiptStore())
        return MissionControlHomeModel(host: host, receiptStore: EmptyReceiptStore())
    }

    @MainActor
    private func makePopulatedModel() -> MissionControlHomeModel {
        let model = makeModel()
        model.seedForSnapshot(
            referenceDate: Self.referenceDate,
            recentReceipts: Self.receiptFixtures,
            browserReceipts: Self.receiptFixtures,
            activeLeases: Self.leaseFixtures,
            performanceHealth: Self.healthFixtures,
            recentExecutions: Self.executionFixtures,
            workflowStepLogs: Self.workflowStepFixtures
        )
        return model
    }

    @MainActor
    private func makeModeModel(_ mode: CryptoMode) -> MissionControlHomeModel {
        var selectedMode = mode
        let host = RuntimeHost(
            receiptStore: EmptyReceiptStore(),
            identity: RuntimeIdentityHooks(
                cryptoModeProvider: { selectedMode },
                cryptoModeSetter: { selectedMode = $0 }
            )
        )
        let model = MissionControlHomeModel(host: host, receiptStore: EmptyReceiptStore())
        model.seedForSnapshot(referenceDate: Self.referenceDate)
        return model
    }

    @MainActor
    private func assertSection(
        _ view: some View,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        #if canImport(AppKit) && !canImport(UIKit)
        guard ProcessInfo.processInfo.environment["MISSION_CONTROL_ENABLE_APPKIT_SNAPSHOTS"] == "1" else {
            throw XCTSkip("AppKit image snapshots require MISSION_CONTROL_ENABLE_APPKIT_SNAPSHOTS=1 in a configured visual snapshot lane.")
        }
        #endif
        let root = NavigationStack { view }
            .frame(width: Self.canvas.width, height: Self.canvas.height)
        let controller = HostController(rootView: AnyView(root))
        controller.view.frame = CGRect(origin: .zero, size: Self.canvas)

        // Tolerant image comparison: exact pixel matching is fragile across hosts/SDKs because of
        // font anti-aliasing and color-profile differences. `perceptualPrecision` absorbs sub-pixel
        // rendering noise while still catching real layout/content regressions.
        assertSnapshot(
            of: controller,
            as: .image(precision: 0.99, perceptualPrecision: 0.97),
            named: name,
            file: file,
            testName: "sections",
            line: line
        )

        try assertSectionRenderedContent(controller, named: name, file: file, line: line)
    }

    /// Fails when a section rendered no rows, so a vacuous baseline can never pass silently.
    ///
    /// Several committed baselines are byte-identical blank canvases — `sections.receipts.png` and
    /// `sections.activity.png` are the *same image* despite being different screens, and each of
    /// `home`, `receipts`, `capabilities`, and `performance` matches its own `-populated` sibling
    /// exactly. A blank canvas compares equal to every other blank canvas, so those baselines pass
    /// forever and hide every regression behind them.
    ///
    /// The cause is not a missing window or layout pass: `SnapshotTesting` already hosts the
    /// controller in its own `UIWindow`, runs the appearance transition, and calls `layoutIfNeeded`
    /// (see `prepareView` / `add(traits:viewController:to:)` in the library). This assertion is what
    /// localizes the real cause on a simulator run instead of guessing at it.
    @MainActor
    private func assertSectionRenderedContent(
        _ controller: HostController,
        named name: String,
        file: StaticString,
        line: UInt
    ) throws {
        #if canImport(UIKit)
        // Every section asserted here is `List`- or `Form`-backed, so a collection view must exist.
        // Failing when it is absent is deliberate: if SwiftUI's backing container changes, a loud
        // failure is better than silently skipping the only check that catches blank baselines.
        guard let collectionView = controller.view.firstDescendant(ofType: UICollectionView.self) else {
            XCTFail(
                "\(name): expected a List/Form-backed collection view hosting the section content.",
                file: file,
                line: line
            )
            return
        }
        // Even an empty section renders one row (its "nothing here yet" copy), so zero rows always
        // means the content never rendered.
        XCTAssertFalse(
            collectionView.visibleCells.isEmpty,
            "\(name): rendered no rows, so this baseline asserts nothing.",
            file: file,
            line: line
        )
        #endif
    }

    // MARK: - EPIC P1-100 — Mission Control Core

    @MainActor func testHome() throws { try assertSection(MissionControlHomeContent(model: makeModel()), named: "home") }
    @MainActor func testTimeline() throws { try assertSection(MissionControlTimelineView(model: makeModel()), named: "timeline") }
    @MainActor func testActivity() throws { try assertSection(MissionControlActivityView(model: makeModel()), named: "activity") }
    @MainActor func testMode() throws { try assertSection(MissionControlModeView(model: makeModel()), named: "mode") }

    // MARK: - EPIC P1-200 — Approval & Authority

    @MainActor func testApprovals() throws { try assertSection(MissionControlApprovalsView(model: makeModel()), named: "approvals") }
    @MainActor func testCapabilities() throws { try assertSection(MissionControlCapabilitiesView(model: makeModel()), named: "capabilities") }

    // MARK: - EPIC P1-300 — Receipts

    @MainActor func testReceipts() throws { try assertSection(MissionControlReceiptsView(model: makeModel()), named: "receipts") }

    // MARK: - EPIC P1-400 — Artifacts

    @MainActor func testArtifacts() throws { try assertSection(MissionControlArtifactsView(model: makeModel()), named: "artifacts") }

    // MARK: - EPIC P1-500 — Playbooks & Routines

    @MainActor func testOperators() throws { try assertSection(MissionControlOperatorsView(model: makeModel()), named: "operators") }
    @MainActor func testPlaybooks() throws { try assertSection(MissionControlPlaybooksView(model: makeModel()), named: "playbooks") }
    @MainActor func testRoutines() throws { try assertSection(MissionControlRoutinesView(model: makeModel()), named: "routines") }

    // MARK: - EPIC P1-600 — Performance

    @MainActor func testPerformance() throws { try assertSection(MissionControlPerformanceView(model: makeModel()), named: "performance") }

    // MARK: - Populated-state baselines (deterministic via seedForSnapshot + fixed referenceDate)

    @MainActor func testHomePopulated() throws { try assertSection(MissionControlHomeContent(model: makePopulatedModel()), named: "home-populated") }
    @MainActor func testTimelinePopulated() throws { try assertSection(MissionControlTimelineView(model: makePopulatedModel()), named: "timeline-populated") }
    @MainActor func testActivityPopulated() throws { try assertSection(MissionControlActivityView(model: makePopulatedModel()), named: "activity-populated") }
    @MainActor func testReceiptsPopulated() throws { try assertSection(MissionControlReceiptsView(model: makePopulatedModel()), named: "receipts-populated") }
    @MainActor func testCapabilitiesPopulated() throws { try assertSection(MissionControlCapabilitiesView(model: makePopulatedModel()), named: "capabilities-populated") }
    @MainActor func testPerformancePopulated() throws { try assertSection(MissionControlPerformanceView(model: makePopulatedModel()), named: "performance-populated") }
    @MainActor func testContextPopulated() throws { try assertSection(MissionControlContextView(model: makePopulatedModel()), named: "context-populated") }
    @MainActor func testModeAssistPopulated() throws { try assertSection(MissionControlModeView(model: makeModeModel(.assist)), named: "mode-assist-populated") }
    @MainActor func testModeOperatePopulated() throws { try assertSection(MissionControlModeView(model: makeModeModel(.operate)), named: "mode-operate-populated") }

    // MARK: - Fixtures

    private static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")!
    }

    private static var receiptFixtures: [ReceiptRecord] {
        [
            ReceiptRecord(
                id: uuid(1), sequenceID: 2, createdAt: baseDate.addingTimeInterval(60), actor: .user,
                actorDetail: nil, authorityDetail: nil,
                mode: .observe, trigger: "tool.executed", scope: "runtime",
                summary: "Research brief generated", provenance: "operator", isSuccess: true,
                correlationID: "wf-research", details: ReceiptPayload(values: [:])
            ),
            ReceiptRecord(
                id: uuid(2), sequenceID: 1, createdAt: baseDate, actor: .system,
                actorDetail: .system, authorityDetail: nil,
                mode: .observe, trigger: "tool.blocked", scope: "runtime",
                summary: "On-chain watch blocked in Observe", provenance: "operator", isSuccess: false,
                correlationID: "wf-watch", details: ReceiptPayload(values: [:])
            )
        ]
    }

    private static var leaseFixtures: [CapabilityLease] {
        [
            CapabilityLease(
                id: uuid(30), capability: .playlistManagement,
                grantedTo: ActorRef(kind: .operatorAgent, identifier: "research.brief"),
                grantedAt: baseDate, expiresAt: referenceDate.addingTimeInterval(20 * 60)
            )
        ]
    }

    private static var healthFixtures: [PlaybookHealth] {
        let events = [
            PerformanceEvent(id: uuid(10), playbookID: "research.brief", outcome: .success, durationSeconds: 1.2, recordedAt: baseDate),
            PerformanceEvent(id: uuid(11), playbookID: "research.brief", outcome: .success, durationSeconds: 0.8, requiredIntervention: true, recordedAt: baseDate),
            PerformanceEvent(id: uuid(12), playbookID: "research.brief", outcome: .blocked, durationSeconds: 0.1, recordedAt: baseDate),
            // Two failures with the same reason → a recurring pattern; one with a different reason → a one-off.
            PerformanceEvent(id: uuid(13), playbookID: "research.brief", outcome: .failed, durationSeconds: 0.3, recordedAt: baseDate.addingTimeInterval(60), triggerSource: "schedule", failureReason: "provider timeout"),
            PerformanceEvent(id: uuid(14), playbookID: "research.brief", outcome: .failed, durationSeconds: 0.3, recordedAt: baseDate.addingTimeInterval(120), triggerSource: "schedule", failureReason: "provider timeout"),
            PerformanceEvent(id: uuid(15), playbookID: "research.brief", outcome: .failed, durationSeconds: 0.2, recordedAt: baseDate.addingTimeInterval(180), triggerSource: "manual", failureReason: "rate limited")
        ]
        return [PlaybookHealth(playbookID: "research.brief", events: events)]
    }

    private static var executionFixtures: [ExecutionRecord] {
        [
            ExecutionRecord(
                id: uuid(20), playbookID: "research.brief", triggerSource: .manual,
                actor: .human,
                outcome: .success, artifactID: nil, startedAt: baseDate, durationSeconds: 1.2
            ),
            ExecutionRecord(
                id: uuid(21), playbookID: "research.brief", triggerSource: .schedule,
                actor: .system,
                outcome: .failed, artifactID: nil, startedAt: baseDate.addingTimeInterval(120), durationSeconds: 0.3
            )
        ]
    }

    private static var workflowStepFixtures: [WorkflowStepLog] {
        [
            step("wf-queued", 0, .proposed(proposal(
                "Queue research brief",
                capability: .runPlugin,
                impact: .readOnly,
                correlationID: "wf-queued"
            ))),
            step("wf-running", 10, .proposed(proposal(
                "Index wallet media",
                capability: .audioPlayback,
                impact: .readOnly,
                correlationID: "wf-running",
                parameters: ["account": "vault.eth"]
            ))),
            step("wf-running", 20, .checksEvaluated([
                DeterministicCheckResult(checkID: "context.fresh", passed: true)
            ])),
            step("wf-approval", 30, .proposed(proposal(
                "Prepare treasury transfer",
                capability: .draftTransaction,
                impact: .highRisk,
                correlationID: "wf-approval",
                parameters: ["address": "0xABC"]
            ))),
            step("wf-approval", 40, .decided(.escalate(approvalRequest: ApprovalRequest(
                id: uuid(50),
                proposal: proposal(
                    "Prepare treasury transfer",
                    capability: .draftTransaction,
                    impact: .highRisk,
                    correlationID: "wf-approval",
                    parameters: ["address": "0xABC"]
                ),
                prompt: "Approve treasury transfer draft?"
            )))),
            step("wf-watch", 50, .proposed(proposal(
                "On-chain watch",
                capability: .draftTransaction,
                impact: .highRisk,
                correlationID: "wf-watch",
                parameters: ["address": "0xDEF"]
            ))),
            step("wf-watch", 60, .checksEvaluated([
                DeterministicCheckResult(checkID: "mode.observe", passed: false, detail: "Observe blocks wallet execution")
            ])),
            step("wf-watch", 70, .decided(.block(reason: "Observe mode blocks wallet execution"))),
            step("wf-research", 80, .proposed(proposal(
                "Research brief",
                capability: .runPlugin,
                impact: .readOnly,
                correlationID: "wf-research",
                parameters: ["account": "research.eth"]
            ))),
            step("wf-research", 90, .checksEvaluated([
                DeterministicCheckResult(checkID: "context.fresh", passed: true)
            ])),
            step("wf-research", 100, .decided(.allow)),
            step("wf-research", 110, .executed(artifactID: uuid(40), durationSeconds: 1.2)),
            step("wf-failed", 120, .proposed(proposal(
                "Refresh provider context",
                capability: .runPlugin,
                impact: .readOnly,
                correlationID: "wf-failed"
            ))),
            step("wf-failed", 130, .failed(reason: "Provider timed out"))
        ]
    }

    private static func proposal(
        _ intent: String,
        capability: CapabilityID,
        impact: ActionImpactClass,
        correlationID: String,
        parameters: [String: String] = [:]
    ) -> ActionProposal {
        ActionProposal(
            actor: .system,
            intent: intent,
            capability: capability,
            impact: impact,
            correlationID: correlationID,
            parameters: parameters
        )
    }

    private static func step(
        _ correlationID: String,
        _ seconds: TimeInterval,
        _ event: WorkflowWorklogEvent
    ) -> WorkflowStepLog {
        WorkflowStepLog(
            id: uuid(Int(seconds) + 100),
            correlationID: correlationID,
            toolID: "snapshot.operator",
            event: event,
            actor: .system,
            timestamp: baseDate.addingTimeInterval(seconds)
        )
    }
}

#if canImport(UIKit)
private extension UIView {
    /// First descendant of `type` in breadth-first order, for reaching the `UICollectionView` that
    /// backs a SwiftUI `List`.
    func firstDescendant<T: UIView>(ofType type: T.Type) -> T? {
        var queue: [UIView] = subviews
        var index = 0
        while index < queue.count {
            let candidate = queue[index]
            index += 1
            if let match = candidate as? T { return match }
            queue.append(contentsOf: candidate.subviews)
        }
        return nil
    }
}
#endif

/// A no-op `ReceiptStore` so the model constructs without any persistence. Returns nothing; `append`
/// is never exercised by empty-state snapshots.
private final class EmptyReceiptStore: ReceiptStore, @unchecked Sendable {
    enum Unsupported: Error { case append }
    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord { throw Unsupported.append }
    func latest(limit: Int) async throws -> [ReceiptRecord] { [] }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] { [] }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { }
}
