import CapabilitiesCore
import ReceiptsCore
import AuralisPrimaryModels
import Foundation

public enum MusicReceiptActorValue: String, Sendable {
    case user
    case system
    case `operator`
    case plugin

    var receiptActor: ReceiptActor {
        switch self {
        case .user:
            return .user
        case .system, .operator, .plugin:
            return .system
        }
    }
}

public enum MusicReceiptTriggerCause: String, Sendable {
    case userInitiated = "user_initiated"
    case systemSync = "system_sync"
    case operatorAction = "operator_action"
    case pluginAction = "plugin_action"
    case autoAdvance = "auto_advance"
    case dryRun = "dry_run"
    case policyDenied = "policy_denied"

    var provenance: String {
        switch self {
        case .userInitiated:
            return "user_provided"
        case .systemSync, .dryRun, .autoAdvance:
            return "local_cache"
        case .operatorAction:
            return "operator"
        case .pluginAction:
            return "plugin"
        case .policyDenied:
            return "policy"
        }
    }
}

public enum MusicReceiptPolicyDecision: String, Sendable {
    case allowed
    case blocked
    case dryRun = "dry_run"
}

public enum MusicReceiptRollbackAvailability: String, Sendable {
    case none
    case deletePlaylist = "delete_playlist"
    case manualReverseChange = "manual_reverse_change"
}

public struct MusicReceiptContext: Sendable {
    public let triggerCause: MusicReceiptTriggerCause
    public let actor: MusicReceiptActorValue
    public let accountAddress: String?
    public let chain: Chain?
    public let correlationID: String?
    public let surface: String?

    public init(
        triggerCause: MusicReceiptTriggerCause,
        actor: MusicReceiptActorValue = .user,
        accountAddress: String? = nil,
        chain: Chain? = nil,
        correlationID: String? = nil,
        surface: String? = nil
    ) {
        self.triggerCause = triggerCause
        self.actor = actor
        self.accountAddress = accountAddress
        self.chain = chain
        self.correlationID = correlationID
        self.surface = surface
    }
}

public struct MusicPolicyReceiptContext: Sendable {
    public let action: String
    public let capabilityUsed: CapabilityID
    public let reason: String?
    public let receiptContext: MusicReceiptContext

    public init(
        action: String,
        capabilityUsed: CapabilityID,
        reason: String?,
        receiptContext: MusicReceiptContext
    ) {
        self.action = action
        self.capabilityUsed = capabilityUsed
        self.reason = reason
        self.receiptContext = receiptContext
    }
}

public struct MusicReceiptStateSummary: Equatable, Sendable {
    public let values: [String: ReceiptJSONValue]

    public init(values: [String: ReceiptJSONValue]) {
        self.values = values
    }

    public static func playlist(
        playlistID: UUID,
        playlistTitle: String,
        itemCount: Int,
        changedFields: [String] = []
    ) -> MusicReceiptStateSummary {
        var values: [String: ReceiptJSONValue] = [
            "playlistID": .string(playlistID.uuidString),
            "playlistTitle": .string(playlistTitle),
            "itemCount": .number(Double(itemCount))
        ]

        if !changedFields.isEmpty {
            values["changedFields"] = .array(changedFields.sorted().map(ReceiptJSONValue.string))
        }

        return MusicReceiptStateSummary(values: values)
    }

    public static func autoOrganization(candidateCount: Int, collectionCount: Int) -> MusicReceiptStateSummary {
        MusicReceiptStateSummary(
            values: [
                "candidateCount": .number(Double(candidateCount)),
                "collectionCount": .number(Double(collectionCount))
            ]
        )
    }

    public static func classification(
        totalCount: Int,
        playableCount: Int,
        metadataOnlyCount: Int,
        artworkCount: Int
    ) -> MusicReceiptStateSummary {
        MusicReceiptStateSummary(
            values: [
                "totalCount": .number(Double(totalCount)),
                "playableCount": .number(Double(playableCount)),
                "metadataOnlyCount": .number(Double(metadataOnlyCount)),
                "artworkCount": .number(Double(artworkCount))
            ]
        )
    }

    public static func task(
        name: String,
        inputCount: Int,
        outputCount: Int,
        removedCount: Int = 0
    ) -> MusicReceiptStateSummary {
        MusicReceiptStateSummary(
            values: [
                "taskName": .string(name),
                "inputCount": .number(Double(inputCount)),
                "outputCount": .number(Double(outputCount)),
                "removedCount": .number(Double(removedCount))
            ]
        )
    }

    public static func export(
        name: String,
        format: String,
        itemCount: Int
    ) -> MusicReceiptStateSummary {
        MusicReceiptStateSummary(
            values: [
                "exportName": .string(name),
                "format": .string(format),
                "itemCount": .number(Double(itemCount))
            ]
        )
    }
}

extension ReceiptPayloadField {
    static func object(
        _ key: String,
        values: [String: ReceiptJSONValue]
    ) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .object(values),
            sensitivity: .public,
            valueKind: .object
        )
    }

    static func nullableObject(
        _ key: String,
        summary: MusicReceiptStateSummary?
    ) -> ReceiptPayloadField {
        if let summary {
            return .object(key, values: summary.values)
        }

        return .null(key)
    }
}
