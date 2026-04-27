import SwiftUI

struct ReceiptTimelineFilterCard: View {
    @Binding var timelineState: ReceiptTimelineState
    let availableScopes: [String]

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Filters")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Status", selection: $timelineState.statusFilter) {
                        ForEach(ReceiptStatusFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        Picker("Actor", selection: $timelineState.actorFilter) {
                            ForEach(ReceiptActorFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }

                        Picker("Scope", selection: $timelineState.selectedScope) {
                            Text("All Scopes").tag(ReceiptTimelineState.allScopesValue)
                            ForEach(availableScopes, id: \.self) { scope in
                                Text(scope).tag(scope)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }
}
