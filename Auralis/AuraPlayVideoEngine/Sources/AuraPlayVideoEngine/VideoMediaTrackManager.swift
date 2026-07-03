import AVFoundation
import CoreMedia
import Foundation

public struct VideoAudioTrack: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let languageCode: String?
    public let isDefault: Bool

    public init(id: String, displayName: String, languageCode: String?, isDefault: Bool) {
        self.id = id
        self.displayName = displayName
        self.languageCode = languageCode
        self.isDefault = isDefault
    }
}

public struct VideoChapter: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let startSeconds: Double
    public let durationSeconds: Double

    public init(id: String, title: String, startSeconds: Double, durationSeconds: Double) {
        self.id = id
        self.title = title
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
    }
}

public struct VideoPlaybackCapabilities: Equatable, Sendable {
    public let hasAudioVariants: Bool
    public let hasLegibleTracks: Bool
    public let hasChapters: Bool
    public let isHighFrameRate: Bool
    public let isSpatialVideo: Bool
    public let supportsExternalPlayback: Bool

    public init(
        hasAudioVariants: Bool,
        hasLegibleTracks: Bool,
        hasChapters: Bool,
        isHighFrameRate: Bool,
        isSpatialVideo: Bool,
        supportsExternalPlayback: Bool
    ) {
        self.hasAudioVariants = hasAudioVariants
        self.hasLegibleTracks = hasLegibleTracks
        self.hasChapters = hasChapters
        self.isHighFrameRate = isHighFrameRate
        self.isSpatialVideo = isSpatialVideo
        self.supportsExternalPlayback = supportsExternalPlayback
    }
}

@MainActor
public struct VideoMediaTrackManager {
    public init() {}

    public func availableAudioTracks(for item: AVPlayerItem) async throws -> [VideoAudioTrack] {
        guard let group = try await item.asset.loadMediaSelectionGroup(for: .audible) else { return [] }
        let defaultOption = group.defaultOption

        return group.options.map { option in
            VideoAudioTrack(
                id: option.displayName + (option.locale?.identifier ?? ""),
                displayName: option.displayName,
                languageCode: option.locale?.language.languageCode?.identifier,
                isDefault: option == defaultOption
            )
        }
    }

    public func select(audioTrack: VideoAudioTrack?, on item: AVPlayerItem) async throws {
        guard let group = try await item.asset.loadMediaSelectionGroup(for: .audible) else { return }
        guard let audioTrack else {
            item.select(nil, in: group)
            return
        }

        let option = group.options.first { option in
            option.displayName == audioTrack.displayName
                && option.locale?.language.languageCode?.identifier == audioTrack.languageCode
        }
        item.select(option, in: group)
    }

    public func chapters(for asset: AVAsset, preferredLanguages: [String] = Locale.preferredLanguages) async throws -> [VideoChapter] {
        let groups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: preferredLanguages)
        var chapters: [VideoChapter] = []
        for group in groups {
            var title = "Chapter"
            for item in group.items {
                if let loadedTitle = try? await item.load(.stringValue) {
                    title = loadedTitle
                    break
                }
            }
            chapters.append(VideoChapter(
                id: "\(group.timeRange.start.seconds)-\(title)",
                title: title,
                startSeconds: group.timeRange.start.validSeconds,
                durationSeconds: group.timeRange.duration.validSeconds
            ))
        }
        return chapters
    }

    public func capabilities(for item: AVPlayerItem) async throws -> VideoPlaybackCapabilities {
        let asset = item.asset
        let audioTracks = try await availableAudioTracks(for: item)
        let legibleGroup = try await asset.loadMediaSelectionGroup(for: .legible)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let chapterList = try await chapters(for: asset)
        let hasChapters = !chapterList.isEmpty
        let isPlayable = try await asset.load(.isPlayable)
        var isHighFrameRate = false
        var isSpatialVideo = false
        for track in videoTracks {
            if try await track.load(.nominalFrameRate) >= 48 {
                isHighFrameRate = true
            }
            let characteristics = try await track.load(.mediaCharacteristics)
            if characteristics.contains(.containsStereoMultiviewVideo)
                || characteristics.contains(.carriesVideoStereoMetadata) {
                isSpatialVideo = true
            }
        }

        return VideoPlaybackCapabilities(
            hasAudioVariants: audioTracks.count > 1,
            hasLegibleTracks: legibleGroup?.options.isEmpty == false,
            hasChapters: hasChapters,
            isHighFrameRate: isHighFrameRate,
            isSpatialVideo: isSpatialVideo,
            supportsExternalPlayback: item.canUseNetworkResourcesForLiveStreamingWhilePaused || isPlayable
        )
    }
}

public final class VideoItemOutputFactory: Sendable {
    public init() {}

    public func pixelBufferOutput(pixelFormatType: OSType = kCVPixelFormatType_32BGRA) -> AVPlayerItemVideoOutput {
        AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormatType
        ])
    }
}

private extension CMTime {
    var validSeconds: Double {
        guard isNumeric, seconds.isFinite else { return 0 }
        return seconds
    }
}
