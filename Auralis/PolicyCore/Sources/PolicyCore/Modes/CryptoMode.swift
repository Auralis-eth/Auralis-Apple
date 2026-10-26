import Foundation
import ReceiptsCore

/// The autonomy posture for **crypto/wallet** capabilities only.
///
/// This is deliberately *not* a global app mode. Per ADR-010, the read-only/gated posture applies only
/// to wallet capabilities (`signMessage`, `approveSpending`, `draftTransaction`, and future custody /
/// signing / WalletConnect). Every non-crypto domain (music, artifacts, playbooks, local preferences)
/// supports full operation and is not governed by this type.
///
public enum CryptoMode: String, Codable, CaseIterable, Equatable, Sendable {
    case observe = "Observe"
    case assist = "Assist"
    case operate = "Operate"

    public var label: String { rawValue }

    public var description: String {
        switch self {
        case .observe:
            return "Read-only. Watch accounts and assets; nothing is signed or sent."
        case .assist:
            return "Prepares drafts and escalates crypto actions for approval."
        case .operate:
            return "Can proceed only when signing evidence, confirmation, and receipt controls pass."
        }
    }

    public var receiptMode: ReceiptMode {
        ReceiptMode(rawValue: rawValue) ?? .observe
    }
}
