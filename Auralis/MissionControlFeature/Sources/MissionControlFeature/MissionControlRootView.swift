import RuntimeCore
import SwiftUI

/// The Mission Control operator console tab. Hosts the operator surfaces behind scalable console
/// navigation over one shared model.
public struct MissionControlRootView: View {
    @State private var model: MissionControlHomeModel
    /// Optional so the `NavigationSplitView` sidebar can drive the detail column via a selection
    /// binding. On a compact-width iPhone this is what makes tapping a sidebar row push the detail;
    /// plain buttons mutating a non-optional state never present the collapsed detail. `nil` means the
    /// sidebar list is showing (compact) or no row is selected.
    @State private var section: Section? = .home
    @State private var artifactPath: [UUID] = []

    private let routedArtifactID: UUID?

    /// The section whose detail is rendered — falls back to ``Section/home`` when the sidebar has no
    /// selection (compact width showing the list), so the detail always has content to show.
    private var selectedSection: Section { section ?? .home }

    enum Section: String, CaseIterable, Identifiable {
        case home = "Home"
        case runGoal = "Run a Goal"
        case timeline = "Timeline"
        case activity = "Activity"
        case sessions = "Sessions"
        case context = "Context"
        case approvals = "Approvals"
        case capabilities = "Powers"
        case receipts = "Receipts"
        case operators = "Operators"
        case artifacts = "Artifacts"
        case playbooks = "Playbooks"
        case routines = "Routines"
        case performance = "Performance"
        case reportCards = "Report Cards"
        case mode = "Mode"

        var id: String { rawValue }
    }

    public init(model: MissionControlHomeModel, routedArtifactID: UUID? = nil) {
        _model = State(initialValue: model)
        self.routedArtifactID = routedArtifactID
    }

    public var body: some View {
        NavigationSplitView {
            // Selection-driven list: the binding is what makes the collapsed compact-width layout push
            // the detail column when a row is tapped (see `section`'s doc comment). Rows must be tagged
            // with the `Section` value (via explicit `ForEach` + `.tag`) so the tag type matches the
            // `Section?` binding — the `List(_:selection:)` data initializer would instead key rows by
            // `Section.ID` (String), which never matches the binding and silently breaks navigation.
            List(selection: $section) {
                ForEach(Section.allCases) { section in
                    Label(section.rawValue, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .navigationTitle("Mission Control")
            .accessibilityIdentifier(MissionControlA11yID.sectionList)
        } detail: {
            NavigationStack(path: $artifactPath) {
                VStack(spacing: 0) {
                    MissionControlPausedBanner(model: model)
                    MissionControlDegradedEvidenceBanner(model: model)
                    MissionControlCoordinationQuarantineBanner(model: model)
                    MissionControlDataQualityBanner(issues: model.dataQualityIssues)
                    content
                }
                    .navigationTitle(selectedSection.rawValue)
                    .toolbar {
                        ToolbarItem {
                            Picker("Section", selection: $section) {
                                ForEach(Section.allCases) { section in
                                    Text(section.rawValue).tag(Section?.some(section))
                                }
                            }
                            .accessibilityLabel("Mission Control section")
                            .accessibilityIdentifier(MissionControlA11yID.sectionPicker)
                        }
                    }
                    .task { await model.loadConsoleAndObserveEvents() }
                    .task(id: routedArtifactID) { await routeToArtifactIfNeeded(routedArtifactID) }
                    .navigationDestination(for: UUID.self) { artifactID in
                        if let artifact = model.artifact(id: artifactID) {
                            MissionControlArtifactDetailView(artifact: artifact, model: model)
                        } else {
                            MissionControlMissingArtifactView(artifactID: artifactID)
                        }
                    }
            }
        }
        .onChange(of: model.host.playbookPersistenceError) { _, errorMessage in
            if let errorMessage {
                model.playbookPersistenceError = errorMessage
            }
        }
        .alert(
            "Playbook Persistence Error",
            isPresented: Binding(
                get: { model.playbookPersistenceError != nil },
                set: { isPresented in
                    if !isPresented {
                        model.playbookPersistenceError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.playbookPersistenceError = nil
            }
        } message: {
            Text(model.playbookPersistenceError ?? "The playbook change could not be saved.")
                .accessibilityIdentifier(MissionControlA11yID.playbookPersistenceError)
        }
        .missionControlApprovalPersistenceAlert(model: model)
    }

    @MainActor
    private func routeToArtifactIfNeeded(_ artifactID: UUID?) async {
        guard let artifactID else { return }
        section = .artifacts
        await model.loadArtifacts()
        if artifactPath.last != artifactID {
            artifactPath = [artifactID]
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedSection {
        case .home: MissionControlHomeContent(model: model)
        case .runGoal: MissionControlRunGoalView(host: model.host, onCompleted: { await model.loadConsole() })
        case .timeline: MissionControlTimelineView(model: model)
        case .activity: MissionControlActivityView(model: model)
        case .sessions: MissionControlSessionsView(model: model)
        case .context: MissionControlContextView(model: model)
        case .approvals: MissionControlApprovalsView(model: model)
        case .capabilities: MissionControlCapabilitiesView(model: model)
        case .receipts: MissionControlReceiptsView(model: model)
        case .operators: MissionControlOperatorsView(model: model)
        case .artifacts: MissionControlArtifactsView(model: model)
        case .playbooks: MissionControlPlaybooksView(model: model)
        case .routines: MissionControlRoutinesView(model: model)
        case .performance: MissionControlPerformanceView(model: model)
        case .reportCards: MissionControlReportCardView(model: model)
        case .mode: MissionControlModeView(model: model)
        }
    }
}

extension View {
    func missionControlApprovalPersistenceAlert(model: MissionControlHomeModel) -> some View {
        alert(
            "Approval Not Saved",
            isPresented: Binding(
                get: { model.approvalPersistenceError != nil },
                set: { isPresented in
                    if !isPresented {
                        model.dismissApprovalPersistenceError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.dismissApprovalPersistenceError()
            }
        } message: {
            Text(model.approvalPersistenceError ?? "The approval was not saved and the action was not executed.")
                .accessibilityIdentifier(MissionControlA11yID.approvalPersistenceError)
        }
    }
}

private struct MissionControlMissingArtifactView: View {
    let artifactID: UUID

    var body: some View {
        ContentUnavailableView(
            "Artifact Not Found",
            systemImage: "archivebox",
            description: Text("Auralis could not resolve artifact \(artifactID.uuidString).")
        )
    }
}

private extension MissionControlRootView.Section {
    var systemImage: String {
        switch self {
        case .home: return "gauge.with.dots.needle.bottom.50percent"
        case .runGoal: return "sparkles"
        case .timeline: return "timeline.selection"
        case .activity: return "waveform.path.ecg"
        case .sessions: return "rectangle.stack.person.crop"
        case .context: return "scope"
        case .approvals: return "checkmark.seal"
        case .capabilities: return "key"
        case .receipts: return "doc.text"
        case .operators: return "sparkles"
        case .artifacts: return "archivebox"
        case .playbooks: return "book.pages"
        case .routines: return "calendar.badge.clock"
        case .performance: return "chart.xyaxis.line"
        case .reportCards: return "checklist"
        case .mode: return "lock.shield"
        }
    }
}
