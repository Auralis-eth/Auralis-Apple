import Foundation
import OSLog
import RuntimeKit
import SocialCore

/// Privacy-safe production diagnostics for Social v1. Durable receipts contain only stable event
/// classifications and public identifiers; unified logging contains classifications only.
struct ReceiptBackedSocialRelayDiagnostics: SocialRelayDiagnostics {
    private let host: RuntimeHost
    private let logger = Logger(subsystem: "Auralis", category: "SocialRelay")

    init(host: RuntimeHost) {
        self.host = host
    }

    func recordQuarantine(reason: SocialRelayQuarantineReason, topic: String) async {
        logger.error("Quarantined inbound social payload reason=\(reason.rawValue, privacy: .public)")
        await host.recordSocialDiagnostic(
            kind: "relay.quarantine",
            reason: reason.rawValue,
            sessionID: nil
        )
    }

    func recordDroppedOutbound(
        reason: SocialRelayQuarantineReason,
        sessionID: UUID,
        eventID: UUID
    ) async {
        logger.error("Dropped outbound social event reason=\(reason.rawValue, privacy: .public)")
        await host.recordSocialDiagnostic(
            kind: "relay.outbound.dropped",
            reason: reason.rawValue,
            sessionID: sessionID,
            eventID: eventID
        )
    }

    func recordRejectedEvent(
        reason: SocialSessionProjection.RejectionReason,
        sessionID: UUID,
        eventID: UUID
    ) async {
        logger.notice("Rejected social event reason=\(reason.rawValue, privacy: .public)")
        await host.recordSocialDiagnostic(
            kind: "event.rejected",
            reason: reason.rawValue,
            sessionID: sessionID,
            eventID: eventID
        )
    }

    func recordOperationalEvent(_ event: SocialRelayOperationalEvent) async {
        let value: String
        switch event {
        case .subscribeSucceeded: value = "subscribe.succeeded"
        case .subscribeFailed: value = "subscribe.failed"
        case .publishSucceeded: value = "publish.succeeded"
        case .publishFailed: value = "publish.failed"
        case .inboundAccepted: value = "inbound.accepted"
        case .prune: value = "retention.pruned"
        }
        logger.info("Social relay operation=\(value, privacy: .public)")
    }
}
