import AVFoundation
import CoreGraphics
import Foundation

public enum VideoPlaybackState: Equatable, Sendable {
    case idle
    case loading(URL)
    case ready(durationSeconds: Double?)
    case playing
    case paused
    case buffering
    case ended
    case failed(VideoPlaybackError)
}

public enum VideoPlaybackError: Error, Equatable, Sendable {
    case unresolvedURL
    case unsupportedVideoFormat
    case videoLoadFailed(String?)
    case pictureInPictureUnsupported
    case noCurrentItem
    case resourceLoadingUnsupported
}

public struct PlaybackTick: Equatable, Sendable {
    public let currentSeconds: Double
    public let durationSeconds: Double?

    public init(currentSeconds: Double, durationSeconds: Double?) {
        self.currentSeconds = currentSeconds
        self.durationSeconds = durationSeconds
    }
}

public enum VideoPlaybackEvent: Equatable, Sendable {
    case stateChanged(VideoPlaybackState)
    case tick(PlaybackTick)
    case didPlayToEnd
    case failedToPlayToEnd(String?)
    case playbackStalled
    case externalPlaybackChanged(Bool)
    case waitingReasonChanged(VideoWaitingReason?)
}

public enum VideoWaitingReason: Equatable, Sendable {
    case evaluatingBufferingRate
    case minimizingStalls
    case noItemToPlay
    case unknown(String?)

    public init(_ reason: AVPlayer.WaitingReason?) {
        guard let reason else {
            self = .unknown(nil)
            return
        }

        switch reason {
        case .evaluatingBufferingRate:
            self = .evaluatingBufferingRate
        case .toMinimizeStalls:
            self = .minimizingStalls
        case .noItemToPlay:
            self = .noItemToPlay
        default:
            self = .unknown(reason.rawValue)
        }
    }
}

public enum VideoSeekKind: Equatable, Sendable {
    case scrub
    case skip
    case resume

    public var tolerance: VideoSeekTolerance {
        switch self {
        case .scrub:
            VideoSeekTolerance(beforeSeconds: 0, afterSeconds: 0)
        case .skip, .resume:
            VideoSeekTolerance(beforeSeconds: 0.15, afterSeconds: 0.15)
        }
    }
}

public struct VideoSeekTolerance: Equatable, Sendable {
    public let beforeSeconds: Double
    public let afterSeconds: Double

    public init(beforeSeconds: Double, afterSeconds: Double) {
        self.beforeSeconds = beforeSeconds
        self.afterSeconds = afterSeconds
    }

    var beforeTime: CMTime {
        CMTime(seconds: beforeSeconds, preferredTimescale: 600)
    }

    var afterTime: CMTime {
        CMTime(seconds: afterSeconds, preferredTimescale: 600)
    }
}

public struct VideoPresentationInfo: Equatable, Sendable {
    public let aspectRatio: Double
    public let isLandscape: Bool
    public let isSquare: Bool

    public init(aspectRatio: Double, isLandscape: Bool, isSquare: Bool) {
        self.aspectRatio = aspectRatio
        self.isLandscape = isLandscape
        self.isSquare = isSquare
    }
}

public struct SubtitleTrack: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let languageCode: String?

    public init(id: String, displayName: String, languageCode: String?) {
        self.id = id
        self.displayName = displayName
        self.languageCode = languageCode
    }
}

public struct AudioDescriptionTrack: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let languageCode: String?

    public init(id: String, displayName: String, languageCode: String?) {
        self.id = id
        self.displayName = displayName
        self.languageCode = languageCode
    }
}

public enum PiPState: Equatable, Sendable {
    case inactive
    case starting
    case active
    case stopping
    case unsupported
}

public protocol VideoPlayableMedia: Sendable {
    var videoMediaID: String { get }
    var videoTitle: String { get }
    var videoArtist: String? { get }
    var videoArtworkURL: URL? { get }
    var resolvedPlaybackURL: URL { get }
}

public struct VideoMediaMetadata: Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String?
    public let artworkURL: URL?

    public init(id: String, title: String, artist: String?, artworkURL: URL?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
    }

    public init(media: some VideoPlayableMedia) {
        self.init(
            id: media.videoMediaID,
            title: media.videoTitle,
            artist: media.videoArtist,
            artworkURL: media.videoArtworkURL
        )
    }
}

public struct StoredVideoPlaybackPosition: Equatable, Sendable {
    public let mediaID: String
    public let positionMilliseconds: Int
    public let durationMilliseconds: Int?

    public init(mediaID: String, positionMilliseconds: Int, durationMilliseconds: Int?) {
        self.mediaID = mediaID
        self.positionMilliseconds = positionMilliseconds
        self.durationMilliseconds = durationMilliseconds
    }
}
