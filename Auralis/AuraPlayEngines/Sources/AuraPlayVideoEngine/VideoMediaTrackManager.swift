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
    public let immersiveMediaProfile: VideoImmersiveMediaProfile
    public let isStereoVideo: Bool
    public let isSpatialVideo: Bool
    public let isAppleImmersiveVideo: Bool
    public let isProjectedMedia: Bool
    public let supportsExternalPlayback: Bool

    public init(
        hasAudioVariants: Bool,
        hasLegibleTracks: Bool,
        hasChapters: Bool,
        isHighFrameRate: Bool,
        immersiveMediaProfile: VideoImmersiveMediaProfile = .standard2D,
        isStereoVideo: Bool? = nil,
        isSpatialVideo: Bool,
        isAppleImmersiveVideo: Bool? = nil,
        isProjectedMedia: Bool? = nil,
        supportsExternalPlayback: Bool
    ) {
        let resolvedProfile = isSpatialVideo && immersiveMediaProfile == .standard2D
            ? .spatialVideo
            : immersiveMediaProfile
        self.hasAudioVariants = hasAudioVariants
        self.hasLegibleTracks = hasLegibleTracks
        self.hasChapters = hasChapters
        self.isHighFrameRate = isHighFrameRate
        self.immersiveMediaProfile = resolvedProfile
        self.isStereoVideo = isStereoVideo ?? (isSpatialVideo || resolvedProfile == .stereo3D)
        self.isSpatialVideo = isSpatialVideo
        self.isAppleImmersiveVideo = isAppleImmersiveVideo ?? (resolvedProfile == .appleImmersiveVideo)
        self.isProjectedMedia = isProjectedMedia ?? (resolvedProfile == .appleProjectedMedia)
        self.supportsExternalPlayback = supportsExternalPlayback
    }
}

@MainActor
public struct VideoMediaTrackManager {
    private let immersiveProfileDetector: any VideoImmersiveMediaProfileDetecting

    public init() {
        self.init(immersiveProfileDetector: AVFoundationImmersiveMediaProfileDetector())
    }

    init(immersiveProfileDetector: any VideoImmersiveMediaProfileDetecting) {
        self.immersiveProfileDetector = immersiveProfileDetector
    }

    init(spatialVideoDetector: any VideoSpatialVideoDetecting) {
        self.immersiveProfileDetector = SpatialVideoDetectorAdapter(detector: spatialVideoDetector)
    }

    public func availableAudioTracks(for item: AVPlayerItem) async throws -> [VideoAudioTrack] {
        guard let group = try await item.asset.loadMediaSelectionGroup(for: .audible) else { return [] }
        let defaultOption = group.defaultOption

        return group.options.enumerated().map { index, option in
            VideoAudioTrack(
                id: trackID(for: option, index: index),
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

        let option = group.options.enumerated().first { index, option in
            trackID(for: option, index: index) == audioTrack.id
        }
        item.select(option?.element, in: group)
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
        var isHighFrameRate = false
        for track in videoTracks {
            if try await track.load(.nominalFrameRate) >= 48 {
                isHighFrameRate = true
            }
        }
        let immersiveMediaProfile = try await immersiveProfileDetector.immersiveMediaProfile(asset: asset)
        let isSpatialVideo = immersiveMediaProfile == .spatialVideo

        return VideoPlaybackCapabilities(
            hasAudioVariants: audioTracks.count > 1,
            hasLegibleTracks: legibleGroup?.options.isEmpty == false,
            hasChapters: hasChapters,
            isHighFrameRate: isHighFrameRate,
            immersiveMediaProfile: immersiveMediaProfile,
            isStereoVideo: immersiveMediaProfile == .stereo3D || immersiveMediaProfile == .spatialVideo,
            isSpatialVideo: isSpatialVideo,
            isAppleImmersiveVideo: immersiveMediaProfile == .appleImmersiveVideo,
            isProjectedMedia: immersiveMediaProfile == .appleProjectedMedia,
            supportsExternalPlayback: immersiveMediaProfile == .standard2D
        )
    }
}

private func trackID(for option: AVMediaSelectionOption, index: Int) -> String {
    [
        String(index),
        option.displayName,
        option.locale?.identifier ?? "und",
    ].joined(separator: "|")
}

@MainActor
protocol VideoImmersiveMediaProfileDetecting {
    func immersiveMediaProfile(asset: AVAsset) async throws -> VideoImmersiveMediaProfile
}

@MainActor
protocol VideoSpatialVideoDetecting {
    func isSpatialVideo(asset: AVAsset) async throws -> Bool
}

struct AVFoundationImmersiveMediaProfileDetector: VideoImmersiveMediaProfileDetecting {
    func immersiveMediaProfile(asset: AVAsset) async throws -> VideoImmersiveMediaProfile {
        let assistantProfile = await playbackAssistantProfile(asset: asset)
        if assistantProfile != .standard2D {
            return assistantProfile
        }
        return try await trackCharacteristicsProfile(asset: asset)
    }

    func playbackConfigurationOptionsProfile(
        _ options: [AVAssetPlaybackConfigurationOption]
    ) -> VideoImmersiveMediaProfile {
        #if os(visionOS)
        if options.contains(.appleImmersiveVideo) {
            return .appleImmersiveVideo
        }
        #endif
        if options.contains(.nonRectilinearProjection) {
            return .appleProjectedMedia
        }
        if options.contains(.spatialVideo) {
            return .spatialVideo
        }
        if options.contains(.stereoVideo) || options.contains(.stereoMultiviewVideo) {
            return .stereo3D
        }
        return .standard2D
    }

    func playbackConfigurationOptionsIndicateSpatialVideo(
        _ options: [AVAssetPlaybackConfigurationOption]
    ) -> Bool {
        playbackConfigurationOptionsProfile(options) == .spatialVideo
    }

    private func playbackAssistantProfile(asset: AVAsset) async -> VideoImmersiveMediaProfile {
        let options = await playbackConfigurationOptions(for: asset)
        return playbackConfigurationOptionsProfile(options)
    }

    private func playbackConfigurationOptions(for asset: AVAsset) async -> [AVAssetPlaybackConfigurationOption] {
        await withCheckedContinuation { continuation in
            let assistant = AVAssetPlaybackAssistant(asset: asset)
            assistant.loadPlaybackConfigurationOptions { options in
                continuation.resume(returning: options)
            }
        }
    }

    private func trackCharacteristicsProfile(asset: AVAsset) async throws -> VideoImmersiveMediaProfile {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        var foundStereoMultiview = false
        for track in videoTracks {
            let characteristics = try await track.load(.mediaCharacteristics)
            if characteristics.contains(.carriesVideoStereoMetadata) {
                return .spatialVideo
            }
            if characteristics.contains(.containsStereoMultiviewVideo) {
                foundStereoMultiview = true
            }
        }
        return foundStereoMultiview ? .stereo3D : .standard2D
    }
}

struct SpatialVideoDetectorAdapter: VideoImmersiveMediaProfileDetecting {
    let detector: any VideoSpatialVideoDetecting

    func immersiveMediaProfile(asset: AVAsset) async throws -> VideoImmersiveMediaProfile {
        try await detector.isSpatialVideo(asset: asset) ? .spatialVideo : .standard2D
    }
}

typealias AVFoundationSpatialVideoDetector = AVFoundationImmersiveMediaProfileDetector

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
