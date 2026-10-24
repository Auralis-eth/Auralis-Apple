import AuralisPrimaryModels
import Foundation
import ReceiptsCore

/// These two convenience initializers keep an `actor:` parameter even though ``ReceiptDraft`` no
/// longer has one, because it is the knob ~30 existing test call sites already turn. The coarse
/// column is now derived from `actorDetail`, so the parameter is translated into a detail here
/// rather than forwarded: `.user` maps to `.human` and everything else to `.system`, which
/// round-trips exactly through `coarseActor`.
extension ReceiptDraft {
    init(
        createdAt: Date = .now,
        actor: ReceiptActor = .system,
        authorityDetail: ReceiptAuthorityDetail? = nil,
        mode: ReceiptMode = .observe,
        trigger: String,
        scope: String,
        summary: String,
        provenance: String,
        isSuccess: Bool,
        correlationID: String? = nil,
        timelineAccountAddress: String? = nil,
        timelineChainRawValue: String? = nil,
        details: ReceiptPayload
    ) {
        self.init(
            createdAt: createdAt,
            actorDetail: actor == .user ? .human : .system,
            authorityDetail: authorityDetail,
            mode: mode,
            trigger: trigger,
            scope: scope,
            summary: summary,
            provenance: provenance,
            isSuccess: isSuccess,
            correlationID: correlationID,
            timelineAccountAddress: timelineAccountAddress,
            timelineChainRawValue: timelineChainRawValue,
            details: details
        )
    }

    init(
        createdAt: Date = .now,
        category: String,
        kind: String,
        correlationID: String? = nil,
        payload: ReceiptPayload,
        actor: ReceiptActor = .system,
        authorityDetail: ReceiptAuthorityDetail? = nil,
        mode: ReceiptMode = .observe,
        summary: String? = nil,
        provenance: String = "local",
        isSuccess: Bool = true,
        timelineAccountAddress: String? = nil,
        timelineChainRawValue: String? = nil
    ) {
        self.init(
            createdAt: createdAt,
            category: category,
            kind: kind,
            correlationID: correlationID,
            payload: payload,
            actorDetail: actor == .user ? .human : .system,
            authorityDetail: authorityDetail,
            mode: mode,
            summary: summary,
            provenance: provenance,
            isSuccess: isSuccess,
            timelineAccountAddress: timelineAccountAddress,
            timelineChainRawValue: timelineChainRawValue
        )
    }
}
