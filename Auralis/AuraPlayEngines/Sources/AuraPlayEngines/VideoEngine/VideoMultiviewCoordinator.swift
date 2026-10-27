import AVFoundation
import Foundation
#if canImport(AVRouting)
import AVRouting
#endif

public struct VideoMultiviewParticipantID: Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }
}

public enum VideoMultiviewSyncMode: Equatable, Sendable {
    case synchronized
    case independent
}

public struct VideoMultiviewRole: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let primary = VideoMultiviewRole(rawValue: 1 << 0)
    public static let secondary = VideoMultiviewRole(rawValue: 1 << 1)
    public static let externalPlaybackPreferred = VideoMultiviewRole(rawValue: 1 << 2)
    public static let nonMixableAudioPreferred = VideoMultiviewRole(rawValue: 1 << 3)
}

public enum VideoNetworkResourcePriority: Equatable, Sendable {
    case automatic
    case high
    case low
}

public struct VideoMultiviewParticipant {
    public let id: VideoMultiviewParticipantID
    public let controller: any VideoPlayerControlling
    public var role: VideoMultiviewRole
    public var networkPriority: VideoNetworkResourcePriority

    public init(
        id: VideoMultiviewParticipantID,
        controller: any VideoPlayerControlling,
        role: VideoMultiviewRole = [.secondary],
        networkPriority: VideoNetworkResourcePriority = .automatic
    ) {
        self.id = id
        self.controller = controller
        self.role = role
        self.networkPriority = networkPriority
    }
}

public enum VideoMultiviewError: Error, Equatable, Sendable {
    case duplicateParticipant(VideoMultiviewParticipantID)
}

@MainActor
protocol VideoPlaybackCoordinating: AnyObject {
    func coordinate(player: AVPlayer, using medium: AVPlaybackCoordinationMedium) throws
}

@MainActor
protocol VideoRoutingPlaybackArbitrating: AnyObject {
    func preferExternalPlaybackParticipant(_ player: AVPlayer?)
    func preferNonMixableAudioParticipant(_ player: AVPlayer?)
}

@MainActor
protocol VideoNetworkResourcePrioritizing: AnyObject {
    func apply(_ priority: VideoNetworkResourcePriority, to player: AVPlayer)
}

@MainActor
public final class VideoMultiviewCoordinator {
    public private(set) var syncMode: VideoMultiviewSyncMode
    public var participantIDs: [VideoMultiviewParticipantID] {
        participants.keys.sorted { $0.rawValue < $1.rawValue }
    }

    private let playbackCoordinator: any VideoPlaybackCoordinating
    private let routingArbiter: any VideoRoutingPlaybackArbitrating
    private let networkPrioritizer: any VideoNetworkResourcePrioritizing
    private let coordinationMedium = AVPlaybackCoordinationMedium()
    private var participants: [VideoMultiviewParticipantID: VideoMultiviewParticipant] = [:]

    public convenience init(syncMode: VideoMultiviewSyncMode = .synchronized) {
        self.init(
            syncMode: syncMode,
            playbackCoordinator: AVFoundationPlaybackCoordinator(),
            routingArbiter: SystemRoutingPlaybackArbiter(),
            networkPrioritizer: AVPlayerNetworkResourcePrioritizer()
        )
    }

    init(
        syncMode: VideoMultiviewSyncMode = .synchronized,
        playbackCoordinator: any VideoPlaybackCoordinating,
        routingArbiter: any VideoRoutingPlaybackArbitrating,
        networkPrioritizer: any VideoNetworkResourcePrioritizing
    ) {
        self.syncMode = syncMode
        self.playbackCoordinator = playbackCoordinator
        self.routingArbiter = routingArbiter
        self.networkPrioritizer = networkPrioritizer
    }

    public func register(_ participant: VideoMultiviewParticipant) throws {
        guard participants[participant.id] == nil else {
            throw VideoMultiviewError.duplicateParticipant(participant.id)
        }

        if syncMode == .synchronized {
            try playbackCoordinator.coordinate(player: participant.controller.player, using: coordinationMedium)
        }

        participants[participant.id] = participant
        networkPrioritizer.apply(participant.networkPriority, to: participant.controller.player)
        applyRoutingPreferences()
    }

    public func unregister(id: VideoMultiviewParticipantID) {
        participants[id] = nil
        applyRoutingPreferences()
    }

    public func updateRole(_ role: VideoMultiviewRole, for id: VideoMultiviewParticipantID) {
        guard var participant = participants[id] else { return }
        participant.role = role
        participants[id] = participant
        applyRoutingPreferences()
    }

    public func updateNetworkPriority(_ priority: VideoNetworkResourcePriority, for id: VideoMultiviewParticipantID) {
        guard var participant = participants[id] else { return }
        participant.networkPriority = priority
        participants[id] = participant
        networkPrioritizer.apply(priority, to: participant.controller.player)
    }

    private func applyRoutingPreferences() {
        routingArbiter.preferExternalPlaybackParticipant(
            preferredPlayer(for: .externalPlaybackPreferred)
        )
        routingArbiter.preferNonMixableAudioParticipant(
            preferredPlayer(for: .nonMixableAudioPreferred)
        )
    }

    private func preferredPlayer(for role: VideoMultiviewRole) -> AVPlayer? {
        participants.values
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .first { $0.role.contains(role) }?
            .controller.player
    }
}

@MainActor
private final class AVFoundationPlaybackCoordinator: VideoPlaybackCoordinating {
    func coordinate(player: AVPlayer, using medium: AVPlaybackCoordinationMedium) throws {
        try player.playbackCoordinator.coordinate(using: medium)
    }
}

@MainActor
private final class SystemRoutingPlaybackArbiter: VideoRoutingPlaybackArbitrating {
    func preferExternalPlaybackParticipant(_ player: AVPlayer?) {
        #if os(iOS) && canImport(AVRouting)
        AVRoutingPlaybackArbiter.shared().preferredParticipantForExternalPlayback = player
        #endif
    }

    func preferNonMixableAudioParticipant(_ player: AVPlayer?) {
        #if os(iOS) && canImport(AVRouting)
        if #available(iOS 27.0, *) {
            AVRoutingPlaybackArbiter.shared().preferredParticipantForNonMixableAudioRoutes = player
        }
        #endif
    }
}

@MainActor
private final class AVPlayerNetworkResourcePrioritizer: VideoNetworkResourcePrioritizing {
    func apply(_ priority: VideoNetworkResourcePriority, to player: AVPlayer) {
        switch priority {
        case .automatic:
            player.networkResourcePriority = .default
        case .high:
            player.networkResourcePriority = .high
        case .low:
            player.networkResourcePriority = .low
        }
    }
}
