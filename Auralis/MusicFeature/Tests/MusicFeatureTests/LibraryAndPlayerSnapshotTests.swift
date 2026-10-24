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

        // Rasterize at a fixed 1x instead of `bitmapImageRepForCachingDisplay(in:)`, which sizes its
        // bitmap by the host display's backing scale factor. That made the output host-dependent: on a
        // Retina machine every snapshot came out at exactly 2x the committed baselines (780x1240 against
        // 390x620), so the suite failed for reasons that had nothing to do with the views. Pinning pixel
        // dimensions to the point size keeps baselines portable across machines and displays.
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width),
            pixelsHigh: Int(height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: Int(width) * 4,
            bitsPerPixel: 32
        ) else {
            Issue.record("Unable to create a bitmap representation for snapshot \(name).")
            return
        }
        // Points == pixels, which is what makes the cached drawing land at 1x.
        bitmap.size = NSSize(width: width, height: height)
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

        compareSnapshot(
            pngData,
            against: referenceData,
            label: "\(normalizedTestName).\(name)",
            path: snapshotURL.path
        )
    }

    // MARK: Tolerant image comparison

    /// Decoded, colour-space-normalized pixels for one snapshot.
    private struct SnapshotPixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]
    }

    /// Largest per-channel difference treated as rendering noise rather than a real change.
    private static let channelTolerance = 8

    /// Fraction of pixels allowed to exceed ``channelTolerance`` before the snapshot is a failure.
    ///
    /// **Set from a measurement, not a guess.** Instrumented at six decimal places against the
    /// committed baselines: all nine snapshots report **0.000000%** — not one pixel in any of them
    /// differs by more than ``channelTolerance``. The sRGB RGBA8 decode below is what actually
    /// removed the host-dependence these baselines used to suffer from; the budget was never
    /// absorbing anything.
    ///
    /// The previous 0.02 was therefore ~4,836 pixels of slack on a ~390×620 snapshot, enough for a
    /// standard 44×44 pt control (1,936 px) to be **completely restyled and still pass** — a
    /// sensitivity gap on the small end, in exchange for headroom nothing was using.
    ///
    /// 0.001 keeps real headroom for renderer drift on an SDK this has not seen — text antialiasing
    /// moves well under 0.1% of pixels at an 8-level tolerance — while putting the failure threshold
    /// at ~242 pixels, smaller than a single glyph. A restyled control now fails. Deliberately not
    /// 0: that is byte-equality by another name, and re-breaking on every SDK bump is the failure
    /// this comparison was written to end.
    private static let differingPixelBudget = 0.001

    /// Compares snapshots on decoded pixels instead of encoded PNG bytes.
    ///
    /// Byte equality on `.png` output was the reason these baselines "drifted" three times
    /// (2026-07-18, 2026-08-27, 2026-09-01) without any view change: PNG encoding is not stable
    /// across SDKs — chunk metadata and zlib output move — and a single flipped bit in sub-pixel
    /// text antialiasing rewrites the whole compressed stream. Re-recording could not fix that,
    /// because a zero-tolerance comparison re-breaks on the next renderer change.
    ///
    /// Decoding both sides into sRGB RGBA8 normalizes away encoder and colour-profile differences,
    /// and the tolerance budget absorbs antialiasing noise while still catching real layout,
    /// content, or colour regressions — those move many pixels far beyond a few levels.
    private func compareSnapshot(_ pngData: Data, against referenceData: Data, label: String, path: String) {
        guard let rendered = Self.canonicalPixels(from: pngData) else {
            Issue.record("Unable to decode the rendered snapshot for \(label).")
            return
        }
        guard let reference = Self.canonicalPixels(from: referenceData) else {
            Issue.record("Unable to decode the reference snapshot at \(path).")
            return
        }

        guard rendered.width == reference.width, rendered.height == reference.height else {
            Issue.record(
                """
                Snapshot \(label) changed size: rendered \(rendered.width)x\(rendered.height), \
                reference \(reference.width)x\(reference.height). This is a layout change, not \
                rendering noise — re-record only if it is intended.
                """
            )
            return
        }

        var differingPixels = 0
        var worstChannelDelta = 0
        let pixelCount = rendered.width * rendered.height

        for pixel in 0..<pixelCount {
            let offset = pixel * 4
            var exceedsTolerance = false
            for channel in 0..<4 {
                let delta = abs(Int(rendered.bytes[offset + channel]) - Int(reference.bytes[offset + channel]))
                worstChannelDelta = max(worstChannelDelta, delta)
                if delta > Self.channelTolerance {
                    exceedsTolerance = true
                }
            }
            if exceedsTolerance {
                differingPixels += 1
            }
        }

        let differingFraction = pixelCount == 0 ? 0 : Double(differingPixels) / Double(pixelCount)
        #expect(
            differingFraction <= Self.differingPixelBudget,
            """
            Snapshot \(label) does not match its reference image: \
            \(String(format: "%.2f", differingFraction * 100))% of pixels differ by more than \
            \(Self.channelTolerance) levels (budget \(String(format: "%.2f", Self.differingPixelBudget * 100))%, \
            worst channel delta \(worstChannelDelta)). Reference: \(path)
            """
        )
    }

    /// Decodes PNG data into tightly packed sRGB RGBA8 bytes so two snapshots are comparable
    /// regardless of how each one was encoded or which colour profile it carries.
    private static func canonicalPixels(from data: Data) -> SnapshotPixels? {
        guard let cgImage = NSBitmapImageRep(data: data)?.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        return SnapshotPixels(width: width, height: height, bytes: bytes)
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
