import Foundation

public enum MediaSessionEvent: Equatable, Sendable {
    case shouldPause
    case interruptionEndedShouldResume
    case enteredBackground
    case willStop
}

public protocol MediaSessionManaging: Sendable {
    var events: AsyncStream<MediaSessionEvent> { get }
    func configureForPlayback() async throws
}

public extension MediaSessionManaging {
    func configureForVideoPlayback() async throws {
        try await configureForPlayback()
    }
}

public struct MediaShareActivityID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public struct SharedMediaActivityIdentifier: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public var isReverseDNSStyle: Bool {
        rawValue.split(separator: ".").count >= 3 && rawValue.contains(".")
    }
}

public struct MediaParticipantID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public struct SharedMediaSessionID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public struct SharedMediaQueueID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public enum SharedMediaActivityType: String, Codable, Sendable {
    case generic
    case listenTogether
    case watchTogether
    case playTogether
    case workoutTogether
    case shopTogether
    case readTogether
    case learnTogether
    case createTogether
}

public enum SharedMediaGroupContext: String, Codable, Sendable, CaseIterable {
    case faceTime
    case messages
    case airDrop
}

public enum SharedMediaSupportedPlatform: String, Codable, Sendable, CaseIterable {
    case iOS
    case iPadOS
    case macOS
    case tvOS
    case visionOS
}

public struct SharedMediaActivityIdentity: Equatable, Codable, Sendable {
    public let id: MediaShareActivityID
    public let activityIdentifier: SharedMediaActivityIdentifier
    public let title: String
    public let subtitle: String?
    public let previewImageID: String?
    public let fallbackURL: URL?
    public let contentKind: AuraPlayableContentKind
    public let activityType: SharedMediaActivityType
    public let launchPayload: [String: String]

    public init(
        id: MediaShareActivityID,
        activityIdentifier: SharedMediaActivityIdentifier? = nil,
        title: String,
        subtitle: String? = nil,
        previewImageID: String? = nil,
        fallbackURL: URL? = nil,
        contentKind: AuraPlayableContentKind = .unknown,
        activityType: SharedMediaActivityType = .generic,
        launchPayload: [String: String] = [:]
    ) {
        self.id = id
        self.activityIdentifier = activityIdentifier ?? SharedMediaActivityIdentifier(rawValue: id.rawValue)
        self.title = title
        self.subtitle = subtitle
        self.previewImageID = previewImageID
        self.fallbackURL = fallbackURL
        self.contentKind = contentKind
        self.activityType = activityType
        self.launchPayload = launchPayload
    }
}

public enum SharedMediaActivityActivationState: String, Codable, Sendable {
    case staged
    case activated
    case ended
}

public enum SharedMediaActivityLaunchSurface: String, Codable, Sendable, CaseIterable {
    case shareSheet
    case inAppButton
    case contextualMenu
    case airDrop
}

public enum SharedMediaShareSheetProminence: String, Codable, Sendable {
    case prominent
    case standard
    case excluded
}

public struct SharedMediaActivityLaunchPolicy: Equatable, Codable, Sendable {
    public let supportedSurfaces: Set<SharedMediaActivityLaunchSurface>
    public let supportedGroupContexts: Set<SharedMediaGroupContext>
    public let supportedPlatforms: Set<SharedMediaSupportedPlatform>
    public let shareSheetProminence: SharedMediaShareSheetProminence
    public let requiresExistingGroupSession: Bool

    public init(
        supportedSurfaces: Set<SharedMediaActivityLaunchSurface> = [.shareSheet, .inAppButton, .airDrop],
        supportedGroupContexts: Set<SharedMediaGroupContext> = Set(SharedMediaGroupContext.allCases),
        supportedPlatforms: Set<SharedMediaSupportedPlatform> = Set(SharedMediaSupportedPlatform.allCases),
        shareSheetProminence: SharedMediaShareSheetProminence = .prominent,
        requiresExistingGroupSession: Bool = false
    ) {
        self.supportedSurfaces = supportedSurfaces
        self.supportedGroupContexts = supportedGroupContexts
        self.supportedPlatforms = supportedPlatforms
        self.shareSheetProminence = shareSheetProminence
        self.requiresExistingGroupSession = requiresExistingGroupSession
    }

    public var shouldRegisterGroupActivityWithShareSheet: Bool {
        (supportedSurfaces.contains(.shareSheet) || supportedSurfaces.contains(.airDrop))
            && shareSheetProminence != .excluded
    }

    public var shouldPresentInAppSharingController: Bool {
        supportedSurfaces.contains(.inAppButton)
    }

    public func supports(_ context: SharedMediaGroupContext, on platform: SharedMediaSupportedPlatform) -> Bool {
        supportedGroupContexts.contains(context) && supportedPlatforms.contains(platform)
    }
}

public struct SharedMediaActivityMetadataQuality: Equatable, Codable, Sendable {
    public let hasSpecificTitle: Bool
    public let hasPreviewImage: Bool
    public let hasFallbackURL: Bool
    public let activityType: SharedMediaActivityType

    public init(activity: SharedMediaActivityIdentity) {
        self.hasSpecificTitle = activity.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        self.hasPreviewImage = activity.previewImageID?.isEmpty == false
        self.hasFallbackURL = activity.fallbackURL != nil
        self.activityType = activity.activityType
    }
}

public enum MediaParticipantPresenceState: String, Codable, Sendable {
    case invited
    case joining
    case inLobby
    case ready
    case active
    case left
}

public struct MediaParticipantPresence: Identifiable, Equatable, Codable, Sendable {
    public let id: MediaParticipantID
    public let displayName: String?
    public let isLocalParticipant: Bool
    public let state: MediaParticipantPresenceState
    public let joinedAt: Date?

    public init(
        id: MediaParticipantID,
        displayName: String? = nil,
        isLocalParticipant: Bool = false,
        state: MediaParticipantPresenceState,
        joinedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.isLocalParticipant = isLocalParticipant
        self.state = state
        self.joinedAt = joinedAt
    }
}

public enum SharedMediaLateJoinPolicy: String, Codable, Sendable {
    case joinAtCurrentPosition
    case waitInLobby
    case observeUntilNextItem
}

public struct SharedMediaLobbyPolicy: Equatable, Codable, Sendable {
    public let lateJoinPolicy: SharedMediaLateJoinPolicy
    public let minimumReadyParticipants: Int
    public let requiresExplicitStart: Bool

    public init(
        lateJoinPolicy: SharedMediaLateJoinPolicy = .joinAtCurrentPosition,
        minimumReadyParticipants: Int = 1,
        requiresExplicitStart: Bool = false
    ) {
        self.lateJoinPolicy = lateJoinPolicy
        self.minimumReadyParticipants = max(1, minimumReadyParticipants)
        self.requiresExplicitStart = requiresExplicitStart
    }
}

public struct SharedMediaQueueIdentity: Equatable, Codable, Sendable {
    public let id: SharedMediaQueueID
    public let itemIDs: [String]
    public let currentItemID: String?
    public let revision: Int

    public init(
        id: SharedMediaQueueID,
        itemIDs: [String],
        currentItemID: String?,
        revision: Int = 0
    ) {
        self.id = id
        self.itemIDs = itemIDs
        self.currentItemID = currentItemID
        self.revision = revision
    }
}

public struct SharedMediaSessionIdentity: Equatable, Codable, Sendable {
    public let id: SharedMediaSessionID
    public let activity: SharedMediaActivityIdentity
    public let queue: SharedMediaQueueIdentity
    public let lobbyPolicy: SharedMediaLobbyPolicy
    public let launchPolicy: SharedMediaActivityLaunchPolicy

    public init(
        id: SharedMediaSessionID,
        activity: SharedMediaActivityIdentity,
        queue: SharedMediaQueueIdentity,
        lobbyPolicy: SharedMediaLobbyPolicy = SharedMediaLobbyPolicy(),
        launchPolicy: SharedMediaActivityLaunchPolicy = SharedMediaActivityLaunchPolicy()
    ) {
        self.id = id
        self.activity = activity
        self.queue = queue
        self.lobbyPolicy = lobbyPolicy
        self.launchPolicy = launchPolicy
    }
}

public enum MediaControlAction: Equatable, Codable, Sendable {
    case play
    case pause
    case seek(seconds: TimeInterval)
    case skipForward(seconds: TimeInterval)
    case skipBackward(seconds: TimeInterval)
    case next
    case previous
    case selectedItem(id: String)
    case queueChanged(revision: Int)
}

public enum MediaSessionChangeOrigin: Equatable, Codable, Sendable {
    case localParticipant
    case remoteParticipant(MediaParticipantID)
    case system
}

public struct MediaSessionChangeAttribution: Equatable, Codable, Sendable {
    public let origin: MediaSessionChangeOrigin
    public let action: MediaControlAction
    public let occurredAt: Date?

    public init(
        origin: MediaSessionChangeOrigin,
        action: MediaControlAction,
        occurredAt: Date? = nil
    ) {
        self.origin = origin
        self.action = action
        self.occurredAt = occurredAt
    }
}

public struct SharedMediaSessionSnapshot: Equatable, Codable, Sendable {
    public let identity: SharedMediaSessionIdentity
    public let activationState: SharedMediaActivityActivationState
    public let participants: [MediaParticipantPresence]
    public let lastChange: MediaSessionChangeAttribution?

    public init(
        identity: SharedMediaSessionIdentity,
        activationState: SharedMediaActivityActivationState = .activated,
        participants: [MediaParticipantPresence] = [],
        lastChange: MediaSessionChangeAttribution? = nil
    ) {
        self.identity = identity
        self.activationState = activationState
        self.participants = participants
        self.lastChange = lastChange
    }
}

public enum SharedMediaMessageDeliveryMode: String, Codable, Sendable {
    case reliable
    case unreliable
}

public enum SharedMediaMessagePurpose: String, Codable, Sendable {
    case initialStateContribution
    case authoritativeState
    case controlAction
    case participantPresence
    case transientPlaybackHint
    case realtimeGesture
}

public struct SharedMediaMessagePolicy: Equatable, Codable, Sendable {
    public static let maximumPayloadBytes = 256 * 1024

    public let purpose: SharedMediaMessagePurpose
    public let deliveryMode: SharedMediaMessageDeliveryMode
    public let maximumPayloadBytes: Int

    public init(
        purpose: SharedMediaMessagePurpose,
        deliveryMode: SharedMediaMessageDeliveryMode,
        maximumPayloadBytes: Int = SharedMediaMessagePolicy.maximumPayloadBytes
    ) {
        self.purpose = purpose
        self.deliveryMode = deliveryMode
        self.maximumPayloadBytes = maximumPayloadBytes
    }

    public static let initialStateContribution = SharedMediaMessagePolicy(
        purpose: .initialStateContribution,
        deliveryMode: .reliable
    )

    public static let authoritativeState = SharedMediaMessagePolicy(
        purpose: .authoritativeState,
        deliveryMode: .reliable
    )

    public static let controlAction = SharedMediaMessagePolicy(
        purpose: .controlAction,
        deliveryMode: .reliable
    )

    public static let participantPresence = SharedMediaMessagePolicy(
        purpose: .participantPresence,
        deliveryMode: .reliable
    )

    public static let transientPlaybackHint = SharedMediaMessagePolicy(
        purpose: .transientPlaybackHint,
        deliveryMode: .unreliable
    )

    public static let realtimeGesture = SharedMediaMessagePolicy(
        purpose: .realtimeGesture,
        deliveryMode: .unreliable
    )
}

public struct SharedMediaInitialPlaybackStateContribution: Equatable, Codable, Sendable {
    public let participantID: MediaParticipantID
    public let sessionID: SharedMediaSessionID
    public let queue: SharedMediaQueueIdentity
    public let playbackTick: PlaybackTick
    public let isPlaying: Bool
    public let contributedAt: Date?

    public init(
        participantID: MediaParticipantID,
        sessionID: SharedMediaSessionID,
        queue: SharedMediaQueueIdentity,
        playbackTick: PlaybackTick,
        isPlaying: Bool,
        contributedAt: Date? = nil
    ) {
        self.participantID = participantID
        self.sessionID = sessionID
        self.queue = queue
        self.playbackTick = playbackTick
        self.isPlaying = isPlaying
        self.contributedAt = contributedAt
    }
}

public struct SharedMediaAttachmentID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public enum SharedMediaAttachmentKind: String, Codable, Sendable {
    case image
    case audio
    case video
    case document
    case annotation
    case userGeneratedData
    case other
}

public enum SharedMediaAttachmentLifecycle: String, Codable, Sendable {
    case availableWhileSessionHasParticipants
    case removed
}

public struct SharedMediaAttachmentPolicy: Equatable, Codable, Sendable {
    public static let maximumPayloadBytes = 100 * 1024 * 1024

    public let maximumPayloadBytes: Int
    public let supportsLateJoinerCatchUpWithoutReupload: Bool
    public let requiresEndToEndEncryption: Bool
    public let lifecycle: SharedMediaAttachmentLifecycle

    public init(
        maximumPayloadBytes: Int = SharedMediaAttachmentPolicy.maximumPayloadBytes,
        supportsLateJoinerCatchUpWithoutReupload: Bool = true,
        requiresEndToEndEncryption: Bool = true,
        lifecycle: SharedMediaAttachmentLifecycle = .availableWhileSessionHasParticipants
    ) {
        self.maximumPayloadBytes = maximumPayloadBytes
        self.supportsLateJoinerCatchUpWithoutReupload = supportsLateJoinerCatchUpWithoutReupload
        self.requiresEndToEndEncryption = requiresEndToEndEncryption
        self.lifecycle = lifecycle
    }

    public func permitsPayload(byteCount: Int) -> Bool {
        byteCount >= 0 && byteCount <= maximumPayloadBytes
    }
}

public struct SharedMediaAttachmentMetadata: Equatable, Codable, Sendable {
    public let id: SharedMediaAttachmentID
    public let kind: SharedMediaAttachmentKind
    public let displayName: String?
    public let byteCount: Int
    public let contentType: String?
    public let sourceParticipantID: MediaParticipantID?
    public let createdAt: Date?

    public init(
        id: SharedMediaAttachmentID,
        kind: SharedMediaAttachmentKind,
        displayName: String? = nil,
        byteCount: Int,
        contentType: String? = nil,
        sourceParticipantID: MediaParticipantID? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.byteCount = byteCount
        self.contentType = contentType
        self.sourceParticipantID = sourceParticipantID
        self.createdAt = createdAt
    }
}

public struct SharedMediaAttachmentManifest: Equatable, Codable, Sendable {
    public let sessionID: SharedMediaSessionID
    public let attachments: [SharedMediaAttachmentMetadata]
    public let policy: SharedMediaAttachmentPolicy

    public init(
        sessionID: SharedMediaSessionID,
        attachments: [SharedMediaAttachmentMetadata] = [],
        policy: SharedMediaAttachmentPolicy = SharedMediaAttachmentPolicy()
    ) {
        self.sessionID = sessionID
        self.attachments = attachments
        self.policy = policy
    }

    public var totalByteCount: Int {
        attachments.reduce(0) { $0 + max(0, $1.byteCount) }
    }

    public func isAttachmentAllowed(_ attachment: SharedMediaAttachmentMetadata) -> Bool {
        policy.permitsPayload(byteCount: attachment.byteCount)
    }
}

public enum SharedMediaAttachmentMutation: Equatable, Codable, Sendable {
    case added(SharedMediaAttachmentMetadata)
    case removed(SharedMediaAttachmentID)
}
