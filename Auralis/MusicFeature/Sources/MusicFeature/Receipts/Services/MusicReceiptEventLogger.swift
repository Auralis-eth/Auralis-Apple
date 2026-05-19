import CapabilitiesCore
import ReceiptsCore
import AuralisPrimaryModels
import Foundation
import OSLog

@MainActor
public struct MusicReceiptEventLogger {
    private let receiptStore: any ReceiptStore
    private let payloadSanitizer: any ReceiptPayloadSanitizing
    private let logger = Logger(subsystem: "Auralis", category: "MusicReceipts")

    public init(
        receiptStore: any ReceiptStore,
        payloadSanitizer: any ReceiptPayloadSanitizing = DefaultReceiptPayloadSanitizer()
    ) {
        self.receiptStore = receiptStore
        self.payloadSanitizer = payloadSanitizer
    }

    public func recordPlaylistCreated(
        playlistID: UUID,
        playlistTitle: String,
        affectedMediaIDs: [String],
        itemCount: Int,
        context: MusicReceiptContext
    ) async throws -> ReceiptRecord {
        try await append(
            eventType: .playlistCreated,
            capabilityUsed: .playlistManagement,
            policyDecision: .allowed,
            affectedMediaIDs: affectedMediaIDs,
            beforeSummary: nil,
            afterSummary: .playlist(
                playlistID: playlistID,
                playlistTitle: playlistTitle,
                itemCount: itemCount
            ),
            rollbackAvailability: .deletePlaylist,
            context: context,
            playlistID: playlistID.uuidString,
            playlistTitle: playlistTitle,
            operation: "create",
            dryRun: nil,
            reason: nil,
            isSuccess: true
        )
    }

    public func recordPlaylistModified(
        playlistID: UUID,
        playlistTitle: String,
        affectedMediaIDs: [String],
        beforeSummary: MusicReceiptStateSummary,
        afterSummary: MusicReceiptStateSummary,
        changedFields: [String],
        context: MusicReceiptContext
    ) async throws -> ReceiptRecord {
        try await append(
            eventType: .playlistModified,
            capabilityUsed: .playlistManagement,
            policyDecision: .allowed,
            affectedMediaIDs: affectedMediaIDs,
            beforeSummary: beforeSummary,
            afterSummary: afterSummary,
            rollbackAvailability: .manualReverseChange,
            context: context,
            playlistID: playlistID.uuidString,
            playlistTitle: playlistTitle,
            operation: changedFields.sorted().joined(separator: ","),
            dryRun: nil,
            reason: nil,
            isSuccess: true
        )
    }

    public func recordAutoOrganizationRun(
        affectedMediaIDs: [String],
        beforeSummary: MusicReceiptStateSummary?,
        afterSummary: MusicReceiptStateSummary?,
        reason: String?,
        context: MusicReceiptContext
    ) async throws -> ReceiptRecord {
        try await append(
            eventType: .autoOrganizationRun,
            capabilityUsed: .autoOrganization,
            policyDecision: .dryRun,
            affectedMediaIDs: affectedMediaIDs,
            beforeSummary: beforeSummary,
            afterSummary: afterSummary,
            rollbackAvailability: .none,
            context: context,
            playlistID: nil,
            playlistTitle: nil,
            operation: "dry_run",
            dryRun: true,
            reason: reason,
            isSuccess: true
        )
    }

    public func recordMediaClassified(
        affectedMediaIDs: [String],
        beforeSummary: MusicReceiptStateSummary?,
        afterSummary: MusicReceiptStateSummary,
        context: MusicReceiptContext
    ) async throws -> ReceiptRecord {
        try await append(
            eventType: .mediaClassified,
            capabilityUsed: .musicLibraryClassification,
            policyDecision: .allowed,
            affectedMediaIDs: affectedMediaIDs,
            beforeSummary: beforeSummary,
            afterSummary: afterSummary,
            rollbackAvailability: .none,
            context: context,
            playlistID: nil,
            playlistTitle: nil,
            operation: "classify",
            dryRun: nil,
            reason: nil,
            isSuccess: true
        )
    }

    public func recordMetadataOverrideApplied(
        affectedMediaIDs: [String],
        beforeSummary: MusicReceiptStateSummary?,
        afterSummary: MusicReceiptStateSummary,
        reason: String?,
        context: MusicReceiptContext
    ) async throws -> ReceiptRecord {
        try await append(
            eventType: .metadataOverrideApplied,
            capabilityUsed: .metadataOverride,
            policyDecision: .allowed,
            affectedMediaIDs: affectedMediaIDs,
            beforeSummary: beforeSummary,
            afterSummary: afterSummary,
            rollbackAvailability: .manualReverseChange,
            context: context,
            playlistID: nil,
            playlistTitle: nil,
            operation: "apply_override",
            dryRun: nil,
            reason: reason,
            isSuccess: true
        )
    }

    public func recordPolicyBlocked(
        action: String,
        capabilityUsed: CapabilityID,
        reason: String?,
        context: MusicReceiptContext
    ) async throws -> ReceiptRecord {
        try await append(
            eventType: .policyBlocked,
            capabilityUsed: capabilityUsed,
            policyDecision: .blocked,
            affectedMediaIDs: [],
            beforeSummary: nil,
            afterSummary: nil,
            rollbackAvailability: .none,
            context: context,
            playlistID: nil,
            playlistTitle: nil,
            operation: action,
            dryRun: nil,
            reason: reason,
            isSuccess: false
        )
    }

    public func recordBackgroundMusicTaskRun(
        taskName: String,
        affectedMediaIDs: [String],
        beforeSummary: MusicReceiptStateSummary?,
        afterSummary: MusicReceiptStateSummary?,
        context: MusicReceiptContext
    ) async throws -> ReceiptRecord {
        try await append(
            eventType: .backgroundMusicTaskRun,
            capabilityUsed: .backgroundMusicTask,
            policyDecision: .allowed,
            affectedMediaIDs: affectedMediaIDs,
            beforeSummary: beforeSummary,
            afterSummary: afterSummary,
            rollbackAvailability: .none,
            context: context,
            playlistID: nil,
            playlistTitle: nil,
            operation: taskName,
            dryRun: nil,
            reason: nil,
            isSuccess: true
        )
    }

    public func recordExportCreated(
        exportName: String,
        format: String,
        affectedMediaIDs: [String],
        itemCount: Int,
        context: MusicReceiptContext
    ) async throws -> ReceiptRecord {
        try await append(
            eventType: .exportCreated,
            capabilityUsed: .musicExport,
            policyDecision: .allowed,
            affectedMediaIDs: affectedMediaIDs,
            beforeSummary: nil,
            afterSummary: .export(
                name: exportName,
                format: format,
                itemCount: itemCount
            ),
            rollbackAvailability: .manualReverseChange,
            context: context,
            playlistID: nil,
            playlistTitle: nil,
            operation: "create_export",
            dryRun: nil,
            reason: nil,
            isSuccess: true
        )
    }

    public func recordQueueChanged(
        operation: String,
        affectedMediaIDs: [String],
        beforeSummary: MusicReceiptStateSummary?,
        afterSummary: MusicReceiptStateSummary?,
        context: MusicReceiptContext
    ) async throws -> ReceiptRecord {
        try await append(
            eventType: .queueChanged,
            capabilityUsed: .playbackQueue,
            policyDecision: .allowed,
            affectedMediaIDs: affectedMediaIDs,
            beforeSummary: beforeSummary,
            afterSummary: afterSummary,
            rollbackAvailability: .manualReverseChange,
            context: context,
            playlistID: nil,
            playlistTitle: nil,
            operation: operation,
            dryRun: nil,
            reason: nil,
            isSuccess: true
        )
    }

    public func recordPlaybackStarted(
        mediaID: String,
        title: String?,
        artist: String?,
        context: MusicReceiptContext
    ) async throws -> ReceiptRecord {
        try await append(
            eventType: .playbackStarted,
            capabilityUsed: .audioPlayback,
            policyDecision: .allowed,
            affectedMediaIDs: [mediaID],
            beforeSummary: nil,
            afterSummary: MusicReceiptStateSummary(
                values: [
                    "trackID": .string(mediaID),
                    "title": title.map(ReceiptJSONValue.string) ?? .null,
                    "artist": artist.map(ReceiptJSONValue.string) ?? .null
                ]
            ),
            rollbackAvailability: .manualReverseChange,
            context: context,
            playlistID: nil,
            playlistTitle: nil,
            operation: "start",
            dryRun: nil,
            reason: nil,
            isSuccess: true
        )
    }

    public func recordPlaybackCompleted(
        mediaID: String,
        title: String?,
        artist: String?,
        context: MusicReceiptContext
    ) async throws -> ReceiptRecord {
        try await append(
            eventType: .playbackCompleted,
            capabilityUsed: .audioPlayback,
            policyDecision: .allowed,
            affectedMediaIDs: [mediaID],
            beforeSummary: MusicReceiptStateSummary(
                values: [
                    "trackID": .string(mediaID),
                    "title": title.map(ReceiptJSONValue.string) ?? .null,
                    "artist": artist.map(ReceiptJSONValue.string) ?? .null
                ]
            ),
            afterSummary: nil,
            rollbackAvailability: .none,
            context: context,
            playlistID: nil,
            playlistTitle: nil,
            operation: "complete",
            dryRun: nil,
            reason: nil,
            isSuccess: true
        )
    }
}

@MainActor
private extension MusicReceiptEventLogger {
    func append(
        eventType: MusicReceiptEventType,
        capabilityUsed: CapabilityID,
        policyDecision: MusicReceiptPolicyDecision,
        affectedMediaIDs: [String],
        beforeSummary: MusicReceiptStateSummary?,
        afterSummary: MusicReceiptStateSummary?,
        rollbackAvailability: MusicReceiptRollbackAvailability,
        context: MusicReceiptContext,
        playlistID: String?,
        playlistTitle: String?,
        operation: String?,
        dryRun: Bool?,
        reason: String?,
        isSuccess: Bool
    ) async throws -> ReceiptRecord {
        let rawPayload = makePayload(
            eventType: eventType,
            capabilityUsed: capabilityUsed,
            policyDecision: policyDecision,
            affectedMediaIDs: affectedMediaIDs,
            beforeSummary: beforeSummary,
            afterSummary: afterSummary,
            rollbackAvailability: rollbackAvailability,
            context: context,
            playlistID: playlistID,
            playlistTitle: playlistTitle,
            operation: operation,
            dryRun: dryRun,
            reason: reason
        )
        let payload = payloadSanitizer.sanitize(rawPayload)

        do {
            return try await receiptStore.append(
                ReceiptDraft(
                    actor: context.actor.receiptActor,
                    mode: .observe,
                    trigger: eventType.rawValue,
                    scope: eventType.scope,
                    summary: eventType.summary,
                    provenance: context.triggerCause.provenance,
                    isSuccess: isSuccess,
                    correlationID: context.correlationID,
                    timelineAccountAddress: context.accountAddress,
                    timelineChainRawValue: context.chain?.rawValue,
                    details: payload
                )
            )
        } catch {
            logger.error(
                "Failed to append music receipt trigger=\(eventType.rawValue, privacy: .public) correlationID=\(context.correlationID ?? "nil", privacy: .private(mask: .hash)) error=\(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    func makePayload(
        eventType: MusicReceiptEventType,
        capabilityUsed: CapabilityID,
        policyDecision: MusicReceiptPolicyDecision,
        affectedMediaIDs: [String],
        beforeSummary: MusicReceiptStateSummary?,
        afterSummary: MusicReceiptStateSummary?,
        rollbackAvailability: MusicReceiptRollbackAvailability,
        context: MusicReceiptContext,
        playlistID: String?,
        playlistTitle: String?,
        operation: String?,
        dryRun: Bool?,
        reason: String?
    ) -> RawReceiptPayload {
        let timestamp = ISO8601DateFormatter().string(from: .now)
        let dedupedMediaIDs = Array(Set(affectedMediaIDs)).sorted()

        var fields: [ReceiptPayloadField] = [
            .public("eventType", string: eventType.rawValue, kind: .label),
            .public("mode", string: ReceiptMode.observe.rawValue, kind: .label),
            .public("trigger", string: context.triggerCause.rawValue, kind: .label),
            .public("actor", string: context.actor.rawValue, kind: .label),
            .public("capabilityUsed", string: capabilityUsed.rawValue, kind: .label),
            .public("policyDecision", string: policyDecision.rawValue, kind: .label),
            .stringArray("affectedMediaIDs", values: dedupedMediaIDs, kind: .label),
            .nullableObject("beforeSummary", summary: beforeSummary),
            .nullableObject("afterSummary", summary: afterSummary),
            .public("rollbackAvailability", string: rollbackAvailability.rawValue, kind: .label),
            .public("timestamp", string: timestamp, kind: .timestamp)
        ]

        if let surface = context.surface {
            fields.append(.public("surface", string: surface, kind: .label))
        } else {
            fields.append(.null("surface"))
        }

        if let playlistID {
            fields.append(.public("playlistID", string: playlistID, kind: .label))
        } else {
            fields.append(.null("playlistID"))
        }

        if let playlistTitle {
            fields.append(.public("playlistTitle", string: playlistTitle, kind: .label))
        } else {
            fields.append(.null("playlistTitle"))
        }

        if let operation {
            fields.append(.public("operation", string: operation, kind: .label))
        } else {
            fields.append(.null("operation"))
        }

        if let dryRun {
            fields.append(.bool("dryRun", dryRun))
        } else {
            fields.append(.null("dryRun"))
        }

        if let reason {
            fields.append(.redacted("reason", string: reason, kind: .freeformText))
        } else {
            fields.append(.null("reason"))
        }

        if let accountAddress = context.accountAddress {
            fields.append(.hashed("accountAddress", string: accountAddress, kind: .walletAddress))
        }

        if let chain = context.chain {
            fields.append(.public("chain", string: chain.rawValue, kind: .chain))
        } else {
            fields.append(.null("chain"))
        }

        return RawReceiptPayload(fields: fields)
    }
}
