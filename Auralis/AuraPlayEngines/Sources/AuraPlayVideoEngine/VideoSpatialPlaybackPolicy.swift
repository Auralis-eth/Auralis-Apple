import Foundation

public enum VideoImmersiveMediaProfile: Equatable, Sendable {
    case standard2D
    case stereo3D
    case spatialVideo
    case appleProjectedMedia
    case appleImmersiveVideo
    case unknownImmersive

    public var isImmersiveProfile: Bool {
        switch self {
        case .standard2D, .stereo3D:
            false
        case .spatialVideo, .appleProjectedMedia, .appleImmersiveVideo, .unknownImmersive:
            true
        }
    }
}

public enum VideoImmersivePlaybackSurface: Equatable, Sendable {
    case customPlayerLayer
    case avKitExpanded
    case avKitImmersive
    case quickLookPreview
    case realityKitPortal
    case realityKitProgressiveImmersive
    case realityKitFullImmersive
}

public enum VideoImmersivePlaybackPresentation: Equatable, Sendable {
    case standardTwoDimensional
    case inlineTwoDimensionalSpatialFallback
    case stereoFullscreen
    case avKitExpandedImmersivePortal
    case avKitImmersiveExperience
    case quickLookSystemPresentation
    case realityKitPortal
    case realityKitProgressiveImmersive
    case realityKitFullImmersive

    public var shouldMinimizeOverlays: Bool {
        switch self {
        case .standardTwoDimensional:
            false
        case .inlineTwoDimensionalSpatialFallback,
             .stereoFullscreen,
             .avKitExpandedImmersivePortal,
             .avKitImmersiveExperience,
             .quickLookSystemPresentation,
             .realityKitPortal,
             .realityKitProgressiveImmersive,
             .realityKitFullImmersive:
            true
        }
    }

    public var usesHostSystemPresentation: Bool {
        switch self {
        case .avKitExpandedImmersivePortal,
             .avKitImmersiveExperience,
             .quickLookSystemPresentation,
             .realityKitPortal,
             .realityKitProgressiveImmersive,
             .realityKitFullImmersive:
            true
        case .standardTwoDimensional, .inlineTwoDimensionalSpatialFallback, .stereoFullscreen:
            false
        }
    }
}

public struct VideoImmersivePlaybackPolicy: Equatable, Sendable {
    public init() {}

    public func presentation(
        for capabilities: VideoPlaybackCapabilities,
        surface: VideoImmersivePlaybackSurface
    ) -> VideoImmersivePlaybackPresentation {
        presentation(profile: capabilities.immersiveMediaProfile, surface: surface)
    }

    public func presentation(
        profile: VideoImmersiveMediaProfile,
        surface: VideoImmersivePlaybackSurface
    ) -> VideoImmersivePlaybackPresentation {
        guard profile != .standard2D else { return .standardTwoDimensional }

        switch surface {
        case .customPlayerLayer:
            return .inlineTwoDimensionalSpatialFallback
        case .avKitExpanded:
            switch profile {
            case .appleProjectedMedia, .appleImmersiveVideo, .unknownImmersive:
                return .avKitExpandedImmersivePortal
            case .standard2D:
                return .standardTwoDimensional
            case .stereo3D, .spatialVideo:
                return .stereoFullscreen
            }
        case .avKitImmersive:
            return .avKitImmersiveExperience
        case .quickLookPreview:
            return .quickLookSystemPresentation
        case .realityKitPortal:
            return .realityKitPortal
        case .realityKitProgressiveImmersive:
            switch profile {
            case .appleProjectedMedia, .appleImmersiveVideo, .unknownImmersive:
                return .realityKitProgressiveImmersive
            case .standard2D, .stereo3D, .spatialVideo:
                return .realityKitPortal
            }
        case .realityKitFullImmersive:
            switch profile {
            case .spatialVideo:
                return .realityKitFullImmersive
            case .appleProjectedMedia, .appleImmersiveVideo, .unknownImmersive:
                return .realityKitProgressiveImmersive
            case .standard2D, .stereo3D:
                return .stereoFullscreen
            }
        }
    }

    public func presentation(
        isSpatialVideo: Bool,
        surface: VideoImmersivePlaybackSurface
    ) -> VideoImmersivePlaybackPresentation {
        presentation(profile: isSpatialVideo ? .spatialVideo : .standard2D, surface: surface)
    }
}

public typealias VideoSpatialPlaybackSurface = VideoImmersivePlaybackSurface
public typealias VideoSpatialPlaybackPresentation = VideoImmersivePlaybackPresentation
public typealias VideoSpatialPlaybackPolicy = VideoImmersivePlaybackPolicy

public extension VideoImmersivePlaybackSurface {
    static var avPlayerViewControllerFullscreen: VideoImmersivePlaybackSurface {
        .avKitExpanded
    }

    static var systemSpatialPresenter: VideoImmersivePlaybackSurface {
        .quickLookPreview
    }
}

public extension VideoImmersivePlaybackPresentation {
    static var fullSpatialPresentation: VideoImmersivePlaybackPresentation {
        .quickLookSystemPresentation
    }

    var usesSystemSpatialPresentation: Bool {
        switch self {
        case .quickLookSystemPresentation,
             .realityKitPortal,
             .realityKitProgressiveImmersive,
             .realityKitFullImmersive:
            true
        case .standardTwoDimensional,
             .inlineTwoDimensionalSpatialFallback,
             .stereoFullscreen,
             .avKitExpandedImmersivePortal,
             .avKitImmersiveExperience:
            false
        }
    }
}
