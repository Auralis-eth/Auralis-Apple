import Foundation

// Neutral SharePlay session vocabulary — activity identity, launch policy,
// lobby/late-join rules, and queue identity — modeled on GroupActivities
// semantics without importing the framework. Consumed by the AuraPlay video
// engine's integration surface; the app maps these onto the real
// GroupActivities adapter. Types here must stay source-stable for those
// consumers.

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
        rawValue.split(separator: ".").count >= 3
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

/// Mirrors the system's `GroupActivityMetadata.ActivityType` constants so the
/// adapter can map one-to-one without this package importing GroupActivities.
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
