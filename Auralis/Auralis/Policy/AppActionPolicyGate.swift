import OSLog
import PolicyCore
import ReceiptsCore

private let policyGateLogger = Logger(subsystem: "Auralis", category: "Policy")

extension ActionPolicyGate {
    static func attempt(
        _ action: PolicyControlledAction,
        modeState: ModeState,
        receiptStore: any ReceiptStore,
        musicReceiptLogger: MusicReceiptEventLogger? = nil,
        musicPolicyContext: MusicPolicyReceiptContext? = nil,
        payloadSanitizer: any ReceiptPayloadSanitizing = DefaultReceiptPayloadSanitizer(),
        log: @escaping (String) -> Void = { policyGateLogger.notice("\($0, privacy: .public)") }
    ) async -> PolicyGateResult {
        let result = await ActionPolicyGate.attempt(
            action,
            mode: modeState.mode,
            receiptStore: receiptStore,
            payloadSanitizer: payloadSanitizer,
            log: log
        )

        guard !result.isAllowed, let musicReceiptLogger, let musicPolicyContext else {
            return result
        }

        do {
            _ = try await musicReceiptLogger.recordPolicyBlocked(
                action: musicPolicyContext.action,
                capabilityUsed: musicPolicyContext.capabilityUsed,
                reason: musicPolicyContext.reason,
                context: MusicReceiptContext(
                    triggerCause: .policyDenied,
                    actor: musicPolicyContext.receiptContext.actor,
                    accountAddress: musicPolicyContext.receiptContext.accountAddress,
                    chain: musicPolicyContext.receiptContext.chain,
                    correlationID: musicPolicyContext.receiptContext.correlationID,
                    surface: musicPolicyContext.receiptContext.surface
                )
            )
        } catch {
            log("Music policy denial receipt append failed: \(error.localizedDescription)")
        }

        return result
    }
}
