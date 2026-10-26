import AuraUI
import SwiftUI

public struct AuraPlayUpNextSheet<Commander: AuraPlayPlayerCommanding>: View {
    public let queue: AuraPlayPlayerQueuePresentation
    public let commander: Commander

    @Environment(\.dismiss) private var dismiss

    public init(queue: AuraPlayPlayerQueuePresentation, commander: Commander) {
        self.queue = queue
        self.commander = commander
    }

    public var body: some View {
        NavigationStack {
            queueContent
                .navigationTitle("Up Next")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.playerUpNext)
    }

    @ViewBuilder
    private var queueContent: some View {
            #if os(macOS)
            macOSSnapshotContent
            #else
            List {
                if let current = queue.current {
                    Section("Now Playing") {
                        queueRow(current, role: "Current")
                    }
                }

                Section("Up Next") {
                    if queue.upcoming.isEmpty {
                        Text("No upcoming items")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(queue.upcoming) { entry in
                            queueRow(entry, role: "Upcoming")
                                .swipeActions {
                                    Button("Remove", role: .destructive) {
                                        Task { await commander.removeQueueEntry(id: entry.id) }
                                    }
                                }
                                .accessibilityIdentifier(A11yID.AuraPlay.playlistItem(id: entry.id))
                        }
                        .onMove { source, destination in
                            guard let first = source.first,
                                  queue.upcoming.indices.contains(first) else {
                                return
                            }
                            let entry = queue.upcoming[first]
                            Task {
                                await commander.reorderQueueEntry(id: entry.id, toIndex: destination)
                            }
                        }
                    }
                }

                if !queue.history.isEmpty {
                    Section("Recently Played") {
                        ForEach(queue.history) { entry in
                            queueRow(entry, role: "History")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Modes") {
                    Toggle(
                        "Shuffle",
                        isOn: Binding(
                            get: { queue.isShuffleEnabled },
                            set: { isEnabled in
                                Task { await commander.setShuffleEnabled(isEnabled) }
                            }
                        )
                    )

                    Button("Repeat: \(queue.repeatModeTitle)", systemImage: "repeat") {
                        Task { await commander.cycleRepeatMode() }
                    }
                }
            }
            #endif
    }

    #if os(macOS)
    private var macOSSnapshotContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let current = queue.current {
                    queueSection(title: "Now Playing") {
                        queueRow(current, role: "Current")
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                queueSection(title: "Up Next") {
                    if queue.upcoming.isEmpty {
                        Text("No upcoming items")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(queue.upcoming) { entry in
                                HStack(spacing: 10) {
                                    queueRow(entry, role: "Upcoming")
                                    Spacer(minLength: 8)
                                    Button("Remove", systemImage: "minus.circle") {
                                        Task { await commander.removeQueueEntry(id: entry.id) }
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Remove \(entry.title)")
                                }
                                .padding(12)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                .accessibilityIdentifier(A11yID.AuraPlay.playlistItem(id: entry.id))
                            }
                        }
                    }
                }

                if !queue.history.isEmpty {
                    queueSection(title: "Recently Played") {
                        LazyVStack(spacing: 8) {
                            ForEach(queue.history) { entry in
                                queueRow(entry, role: "History")
                                    .foregroundStyle(.secondary)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                queueSection(title: "Modes") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(
                            "Shuffle",
                            isOn: Binding(
                                get: { queue.isShuffleEnabled },
                                set: { isEnabled in
                                    Task { await commander.setShuffleEnabled(isEnabled) }
                                }
                            )
                        )

                        Button("Repeat: \(queue.repeatModeTitle)", systemImage: "repeat") {
                            Task { await commander.cycleRepeatMode() }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func queueSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
    #endif

    private func queueRow(_ entry: AuraPlayPlayerQueueEntryPresentation, role: String) -> some View {
        HStack(spacing: 12) {
            if let artworkURLString = entry.artworkURLString,
               let url = URL(string: artworkURLString) {
                CachedAsyncImage(url: url, mediaAccessibility: .decorative)
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.secondary.opacity(0.18))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "music.note")
                            .accessibilityHidden(true)
                    }
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                if let creator = entry.creator {
                    Text(creator)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(role), \(entry.title)")
    }
}
