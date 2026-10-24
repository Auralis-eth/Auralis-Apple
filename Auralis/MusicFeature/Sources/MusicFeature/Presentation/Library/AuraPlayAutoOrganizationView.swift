import AuraUI
import SwiftUI

struct AuraPlayAutoOrganizationView: View {
    @Bindable var model: AuraPlayRootModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Safe preview") {
                    Label("Reviews playable media and groups it by collection", systemImage: "rectangle.3.group")
                    Label("Does not create, rename, or delete playlists", systemImage: "checkmark.shield")
                }

                Section("Result") {
                    Text(model.autoOrganizationStatus)
                        .accessibilityIdentifier(A11yID.AuraPlay.autoOrganizationStatus)

                    if let result = model.autoOrganizationResult {
                        LabeledContent("Candidate items", value: "\(result.affectedMediaIDs.count)")
                        LabeledContent("Mode", value: result.dryRun ? "Preview only" : "Applied")
                    }
                }

                Section {
                    Button {
                        Task { await model.runAutoOrganizationPreview() }
                    } label: {
                        if model.isAutoOrganizationRunning {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("Analyzing library")
                        } else {
                            Label("Analyze Library", systemImage: "wand.and.sparkles")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(model.isAutoOrganizationRunning)
                    .accessibilityIdentifier(A11yID.AuraPlay.autoOrganizationRun)
                }
            }
            .navigationTitle("Auto-Organize")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .accessibilityIdentifier(A11yID.AuraPlay.autoOrganizationSheet)
        }
    }
}
