import Foundation

/// Compares the ledger this device can see against the last thing the external witness was told.
///
/// A free function on a value type, with no store, no network and no actor, because this is the part
/// worth reading and testing on its own: it is the only place in the package where a verdict rests on
/// evidence the local attacker could not have written.
///
/// **Every rule here is monotonic in the direction the ledger legitimately moves**, which is what
/// makes an honest ledger safe. Receipts are append-only: the mark only rises, an account's
/// `accountSequenceID` only rises, and a row's `chainHash` never changes once written. So each check
/// below fires only on a *backwards* or *sideways* move, and ordinary use — appending, more accounts,
/// more receipts — cannot trip any of them.
public enum ReceiptWitnessComparison {
    /// The local facts this comparison needs. Assembled during the verification pass so the rows are
    /// read once.
    public struct LocalLedger: Equatable, Sendable {
        /// Highest `sequenceID` among rows whose chain hash this build recomputed and matched.
        public let highestVerifiedSequenceID: Int
        /// Every `(accountKey, accountSequenceID) -> chainHash` in the ledger, so a witnessed head can
        /// be located even after the account has grown past it.
        public let chainHashesByAccountSequence: [ReceiptWitnessRowKey: String]
        /// Each account's current tip sequence, so a rolled-back account is distinguishable from a
        /// deleted one.
        public let tipSequenceByAccount: [String: Int]

        public init(
            highestVerifiedSequenceID: Int,
            chainHashesByAccountSequence: [ReceiptWitnessRowKey: String],
            tipSequenceByAccount: [String: Int]
        ) {
            self.highestVerifiedSequenceID = highestVerifiedSequenceID
            self.chainHashesByAccountSequence = chainHashesByAccountSequence
            self.tipSequenceByAccount = tipSequenceByAccount
        }
    }

    /// - Returns: A verdict string when the witness contradicts the ledger, or `nil` when the two
    ///   agree. Never a "cannot tell" — an absent or unreachable witness is the caller's business and
    ///   is reported as an advisory, not through this.
    public static func contradiction(
        local: LocalLedger,
        witnessed: ReceiptLedgerCheckpoint
    ) -> String? {
        // 1. The ledger cannot have got *shorter*. This is the suffix truncation no local check can
        //    see, because the survivors are still a contiguous `1...k` and the only local evidence —
        //    the high-water mark — is an unauthenticated item an attacker who reached the Keychain
        //    could lower to agree with whatever they left behind. The witness holds the number
        //    somewhere the device does not get to correct it.
        if witnessed.ledgerHighWaterMark > local.highestVerifiedSequenceID {
            return "The external witness recorded this ledger reaching receipt \(witnessed.ledgerHighWaterMark), but it now holds no verified receipt past \(local.highestVerifiedSequenceID)."
        }

        for head in witnessed.chainHeads {
            // 2. An account the witness saw cannot simply be gone. Locally this was undetectable
            //    whenever the anchor went with the rows: every other check is per account, so the
            //    survivors link cleanly and nothing is left to notice.
            guard let localTip = local.tipSequenceByAccount[head.accountKey] else {
                return "The external witness recorded receipts for account \(head.accountKey), which this ledger no longer holds."
            }

            // 3. An account cannot have moved backwards.
            if localTip < head.accountSequenceID {
                return "The external witness recorded account \(head.accountKey) reaching receipt \(head.accountSequenceID), but it now ends at \(localTip)."
            }

            // 4. The witnessed receipt must still be *the same receipt*. This is the rewrite check,
            //    and it is the one that cannot be fooled by recomputation: an altered row's own hash
            //    can always be made self-consistent, but it cannot be made equal to a hash that was
            //    written down elsewhere before the alteration.
            //
            //    Looked up by `(account, sequence)` rather than compared against the tip, so it still
            //    holds after the account has legitimately grown past the checkpoint.
            let key = ReceiptWitnessRowKey(accountKey: head.accountKey, accountSequenceID: head.accountSequenceID)
            guard let localHash = local.chainHashesByAccountSequence[key] else {
                return "The external witness recorded receipt \(head.accountSequenceID) for account \(head.accountKey), which is missing from this ledger."
            }
            if localHash != head.chainHash {
                return "Receipt \(head.accountSequenceID) for account \(head.accountKey) does not match the hash the external witness recorded for it, so this ledger was rewritten."
            }
        }

        return nil
    }

    /// The note for a ledger nobody can vouch for from outside.
    ///
    /// Advisory, never a verdict, and that is the decision recorded in the type rather than left to
    /// each caller: a first run, an offline device, a signed-out iCloud account and a service outage
    /// all reach this, and none of them is evidence about the receipts. The same reasoning the mark
    /// already carries — see
    /// ``ReceiptIntegrity/completenessAdvisory(sequenceIDs:highWaterMark:completenessUnconfirmed:)``.
    /// A witness that *answers* and disagrees is a different thing entirely and goes through
    /// ``contradiction(local:witnessed:)``.
    public static func unwitnessedAdvisory(reason: String) -> String {
        "This ledger has not been confirmed against the external witness (\(reason)), so removal of whole accounts or of receipts from the end of it cannot be ruled out."
    }
}

extension String {
    /// `nil` for the empty string, so joining a set of optional advisory notes cannot produce an
    /// advisory that says nothing — which a caller would then surface as though there were something
    /// to investigate.
    var nilWhenEmpty: String? {
        isEmpty ? nil : self
    }
}

/// A `(account, sequence)` address for one receipt, which is what a witnessed head has to be looked up
/// by. `Hashable` so the verification pass can build the lookup in one sweep of the rows.
public struct ReceiptWitnessRowKey: Hashable, Sendable {
    public let accountKey: String
    public let accountSequenceID: Int

    public init(accountKey: String, accountSequenceID: Int) {
        self.accountKey = accountKey
        self.accountSequenceID = accountSequenceID
    }
}
