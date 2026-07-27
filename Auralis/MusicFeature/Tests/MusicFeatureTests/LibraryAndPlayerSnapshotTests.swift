#if os(macOS)
import AppKit
import AuralisPrimaryModels
import Foundation
import MusicFeature
import SwiftUI
import Testing

/// P9-009 / P10-009 snapshot coverage. Rendering runs on the macOS host
/// through `NSHostingView`, so the suite executes with `swift test` and stays
/// deterministic (no artwork URLs, fixed layout sizes, seeded data).
@MainActor
struct LibraryAndPlayerSnapshotTests {
    private func assertViewSnapshot(
        _ view: some View,
        width: CGFloat = 390,
        height: CGFloat = 500,
        named name: String,
        fileID: String = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function
    ) {
        let hostingView = NSHostingView(rootView: AnyView(view.frame(width: width, height: height)))
        hostingView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        hostingView.appearance = NSAppearance(named: .aqua)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            Issue.record("Unable to create a bitmap representation for snapshot \(name).")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            Issue.record("Unable to create PNG data for snapshot \(name).")
            return
        }

        let normalizedTestName = testName.replacingOccurrences(of: "()", with: "")
        let snapshotURL = URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__")
            .appendingPathComponent("LibraryAndPlayerSnapshotTests")
            .appendingPathComponent("\(normalizedTestName).\(name).png")

        if ProcessInfo.processInfo.environment["AURAPLAY_RECORD_SNAPSHOTS"] == "1" {
            do {
                try FileManager.default.createDirectory(
                    at: snapshotURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try pngData.write(to: snapshotURL)
            } catch {
                Issue.record("Unable to record snapshot \(snapshotURL.path): \(error.localizedDescription)")
            }
            return
        }

        guard let referenceData = try? Data(contentsOf: snapshotURL) else {
            Issue.record("Missing reference snapshot at \(snapshotURL.path). Re-run with AURAPLAY_RECORD_SNAPSHOTS=1 to create it.")
            return
        }

        #expect(pngData == referenceData, "Snapshot \(normalizedTestName).\(name) does not match its reference image.")
    }

    // MARK: Library cells (P9-002)

    private func cellViewModel(playable: Bool, current: Bool = false) -> LibraryItemCellViewModel {
        LibraryItemCellViewModel(
            queryItem: MediaItemQueryItem(
                item: AuraPlayLibrarySeed.makeItem(
                    index: 1,
                    title: playable ? "Aurora Drift" : "Ghost Format",
                    artist: "Nova",
                    collection: "Waves",
                    contract: "0xaaa",
                    artwork: nil,
                    isPlayable: playable,
                    duration: 201
                )
            ),
            isCurrent: current
        )
    }

    @Test("Library cell renders playable, dimmed non-playable, and now-playing states")
    func libraryCellStates() {
        let states = VStack(spacing: 16) {
            LibraryItemCell(viewModel: cellViewModel(playable: true), layout: .list, play: {}, open: {}, addToPlaylist: {})
            LibraryItemCell(viewModel: cellViewModel(playable: false), layout: .list, play: {}, open: {}, addToPlaylist: {})
            LibraryItemCell(viewModel: cellViewModel(playable: true, current: true), layout: .list, play: {}, open: {}, addToPlaylist: {})
            HStack(alignment: .top, spacing: 16) {
                LibraryItemCell(viewModel: cellViewModel(playable: true), layout: .grid, play: {}, open: {}, addToPlaylist: {})
                LibraryItemCell(viewModel: cellViewModel(playable: false), layout: .grid, play: {}, open: {}, addToPlaylist: {})
            }
        }
        .padding(20)

        assertViewSnapshot(states, height: 620, named: "light")
        assertViewSnapshot(states.environment(\.colorScheme, .dark), height: 620, named: "dark")
        assertViewSnapshot(
            states.environment(\.dynamicTypeSize, .accessibility3),
            height: 900,
            named: "xxxl"
        )
    }

    // MARK: Full player (P10-001)

    private func playerPresentation(mediaKind: AuraPlayPlayerContentKind) -> AuraPlayPlayerPresentation {
        AuraPlayPlayerPresentation(
            item: AuraPlayPlayerItemPresentation(
                id: "nft-00000",
                title: "Aurora Drift Extended Midnight Rework",
                creator: "Nova",
                collection: "Waves",
                artworkURLString: nil,
                mediaKind: mediaKind,
                chainDisplayName: "Ethereum",
                contractAddress: "0xaaa",
                tokenID: "1"
            ),
            playbackState: .playing,
            position: AuraPlayPlayerPositionPresentation(currentSeconds: 42, durationSeconds: 201),
            queue: AuraPlayPlayerQueuePresentation(
                current: AuraPlayPlayerQueueEntryPresentation(
                    id: "entry-0",
                    mediaItemID: "nft-00000",
                    title: "Aurora Drift Extended Midnight Rework",
                    creator: "Nova",
                    artworkURLString: nil
                ),
                upcoming: [
                    AuraPlayPlayerQueueEntryPresentation(id: "entry-1", mediaItemID: "nft-00001", title: "Basalt", creator: "Nova", artworkURLString: nil),
                    AuraPlayPlayerQueueEntryPresentation(id: "entry-2", mediaItemID: "nft-00001", title: "Basalt", creator: "Nova", artworkURLString: nil)
                ],
                history: []
            ),
            audioCapabilities: mediaKind == .audio ? AuraPlayPlayerAudioCapabilities() : nil,
            videoCapabilities: mediaKind == .video ? AuraPlayPlayerVideoCapabilities(isPiPAvailable: true, hasRoutePicker: true) : nil,
            failureMessage: nil
        )
    }

    @Test("Audio player renders artwork branch with ambient background in light, dark, and XXXL")
    func audioPlayerSnapshots() {
        let player = AuraPlayPlayerView(
            presentation: playerPresentation(mediaKind: .audio),
            commander: NoOpAuraPlayPlayerCommander()
        )

        assertViewSnapshot(player, height: 760, named: "light")
        assertViewSnapshot(AnyView(player).environment(\.colorScheme, .dark), height: 760, named: "dark")
        assertViewSnapshot(
            AnyView(player).environment(\.dynamicTypeSize, .accessibility3),
            height: 1_100,
            named: "xxxl"
        )
    }

    @Test("Video player renders the full-bleed branch with chrome visible")
    func videoPlayerSnapshot() {
        let player = AuraPlayPlayerView(
            presentation: playerPresentation(mediaKind: .video),
            commander: NoOpAuraPlayPlayerCommander()
        ) {
            Color.black
        }

        assertViewSnapshot(player, height: 760, named: "light")
        assertViewSnapshot(AnyView(player).environment(\.colorScheme, .dark), height: 760, named: "dark")
    }

    // MARK: Up Next (P10-003)

    @Test("Up Next keeps duplicate media entries independently identified")
    func upNextDuplicateEntries() {
        let queue = playerPresentation(mediaKind: .audio).queue

        // Same media item twice, distinct queue-entry identities.
        #expect(queue.upcoming.map(\.mediaItemID) == ["nft-00001", "nft-00001"])
        #expect(Set(queue.upcoming.map(\.id)).count == 2)

        let sheet = AuraPlayUpNextSheet(queue: queue, commander: NoOpAuraPlayPlayerCommander())
        assertViewSnapshot(sheet, height: 620, named: "duplicates")
    }
}
#endif
