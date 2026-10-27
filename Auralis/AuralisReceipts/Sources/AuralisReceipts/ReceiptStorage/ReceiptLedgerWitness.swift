import Foundation

/// The external witness: somewhere off this device that remembers what the ledger looked like.
///
/// **Why this exists, and why nothing already in the package could do its job.** Every other integrity
/// signal here is local — the rows, the Keychain anchors, the high-water mark, the envelope-version
/// floor, the signing key. An attacker who can write the device's storage can make local state
/// self-consistent, and six rounds of review kept finding the same shape of hole underneath that
/// fact: some piece of state the attacker controls deciding whether that same state gets checked.
/// ``ReceiptIntegrity/completenessAdvisory(sequenceIDs:highWaterMark:completenessUnconfirmed:)``
/// states the limit outright — "the sound constructions need an external witness — a server, a
/// notary, a published chain — which this package does not have."
///
/// This is that witness. The ledger periodically publishes a ``ReceiptLedgerCheckpoint`` — the
/// sequence it has reached and every account's chain head — to a store outside the device, and
/// verification compares the ledger it can see against the last thing the witness was told. Three
/// things become detectable that were previously **impossible** to detect locally, at any severity:
///
/// - **Suffix truncation.** Deleting whatever was written last leaves the survivors a contiguous
///   `1...k`, so no local check can see it; the mark could only *suggest* it, and an attacker who
///   reached the Keychain could lower the mark to agree.
/// - **Whole-account deletion.** Every local check except the anchor set is per account, so erasing
///   one account's rows plus its anchor leaves the remainder linking cleanly.
/// - **Rewriting history below the witnessed point.** A rewritten row's own hash can be recomputed to
///   match, but it cannot match a hash a third party wrote down first.
///
/// What it does **not** do: it cannot attest to anything that happened after the last checkpoint, so
/// the exposure window is "since the last successful publish". Shrinking that window is what
/// publishing on every append buys.
///
/// - Important: Implementations must be **append-only**. A witness that lets the device replace or
///   delete an earlier checkpoint is not a witness — it is another local store with extra steps, and
///   the whole argument above collapses.
public protocol ReceiptLedgerWitnessing: Sendable {
    /// Records a checkpoint. Best-effort by contract: the ledger treats a failure here as a degraded
    /// witness rather than a failed write, so a receipt is never lost because the network was down.
    func publish(_ checkpoint: ReceiptLedgerCheckpoint) async throws

    /// The most recently witnessed checkpoint, or `nil` when this ledger has never been witnessed.
    ///
    /// Only the latest is needed, and that is not a shortcut: the properties checked against it are
    /// monotonic — the mark only rises, an account's `accountSequenceID` only rises — so the newest
    /// checkpoint implies every older one.
    ///
    /// The distinction between `nil` and a throw is load-bearing and must be kept: `nil` means *this
    /// witness has no record*, which on a first run is the honest truth, while a throw means *cannot
    /// reach the witness*, which says nothing about the ledger. Verification reports them
    /// differently, and neither is a verdict — see
    /// ``ReceiptWitnessComparison/compare(local:witnessed:)``.
    func latestCheckpoint() async throws -> ReceiptLedgerCheckpoint?
}

/// What the ledger looked like at one moment, as told to a party that cannot be leaned on later.
///
/// Deliberately small, and every field is here because it closes something local state cannot:
/// ``ledgerHighWaterMark`` catches a deleted suffix, ``chainHeads`` catches a deleted or rewritten or
/// rolled-back account.
///
/// Carries no signature. That is not an oversight: the signing key is `ThisDeviceOnly` and *usable*
/// by anyone with device access even when it cannot be extracted, so a self-signature would prove
/// nothing to anybody about a device that has been written to. The integrity boundary is the witness
/// store's own — its refusal to let this device rewrite history it already accepted.
public struct ReceiptLedgerCheckpoint: Codable, Equatable, Sendable {
    /// The highest `sequenceID` the ledger had **verified** at publish time.
    ///
    /// Verified, not merely present, for the reason the mark heal is restricted the same way: a row
    /// this build could not recompute has a `sequenceID` covered by nothing, and publishing it would
    /// let an attacker write an arbitrary number into the witness — durably, and to a place designed
    /// not to accept corrections.
    public let ledgerHighWaterMark: Int
    /// Every account's tip at publish time. Reuses ``ReceiptProvenanceChainHead`` rather than
    /// redeclaring the same three fields, so the export manifest and the witness cannot drift.
    public let chainHeads: [ReceiptProvenanceChainHead]
    public let recordCount: Int
    /// The device clock at publish time. **Advisory only** — an attacker who can write the store can
    /// also move the clock, so nothing in verification depends on it. It is here so a person reading a
    /// witness record can see roughly when it was made; a witness store that keeps its own
    /// server-side timestamp should be trusted over this.
    public let publishedAt: Date

    public init(
        ledgerHighWaterMark: Int,
        chainHeads: [ReceiptProvenanceChainHead],
        recordCount: Int,
        publishedAt: Date
    ) {
        self.ledgerHighWaterMark = ledgerHighWaterMark
        self.chainHeads = chainHeads.sorted { $0.accountKey < $1.accountKey }
        self.recordCount = recordCount
        self.publishedAt = publishedAt
    }
}

public enum ReceiptLedgerWitnessError: LocalizedError, Equatable, Sendable {
    /// No witness is configured for this ledger. Distinct from a reachability failure: nothing is
    /// broken, there is simply nobody to ask.
    case notConfigured
    case unreachable(String)
    /// The witness rejected a checkpoint that moves backwards. Append-only stores are entitled to
    /// refuse, and the ledger must not treat that as a reason to stop appending receipts.
    case wouldRegress(witnessed: Int, offered: Int)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No external receipt-ledger witness is configured."
        case let .unreachable(reason):
            return "The external receipt-ledger witness could not be reached: \(reason)."
        case let .wouldRegress(witnessed, offered):
            return "The witness already holds sequence \(witnessed) and will not accept \(offered)."
        }
    }
}

/// The default when no witness is wired up: reports honestly that there is none.
///
/// Deliberately **not** a silent no-op that also returns `nil` from ``latestCheckpoint()``. `nil`
/// means "witnessed never, by a witness that exists", and conflating that with "no witness
/// configured" is how a missing control comes to look like a satisfied one — the same footgun as the
/// defaulted signer on ``ReceiptPersistenceStore/signer``. This throws, so verification attaches its
/// "not witnessed" advisory and a person can tell the difference.
public struct UnconfiguredReceiptLedgerWitness: ReceiptLedgerWitnessing {
    public init() { }

    public func publish(_ checkpoint: ReceiptLedgerCheckpoint) async throws {
        throw ReceiptLedgerWitnessError.notConfigured
    }

    public func latestCheckpoint() async throws -> ReceiptLedgerCheckpoint? {
        throw ReceiptLedgerWitnessError.notConfigured
    }
}

/// An in-process witness for tests and previews.
///
/// **Append-only, enforced**, because that is the one property the real thing is trusted for: a double
/// that let a checkpoint move backwards would pass tests the CloudKit witness fails, and it would pass
/// them for exactly the ledger states this whole mechanism exists to catch.
public actor InMemoryReceiptLedgerWitness: ReceiptLedgerWitnessing {
    private var checkpoint: ReceiptLedgerCheckpoint?
    private var isUnreachable = false

    public init() { }

    /// Simulates a witness that cannot be reached, which must degrade rather than accuse.
    public func setUnreachable(_ unreachable: Bool) {
        isUnreachable = unreachable
    }

    public func publish(_ newCheckpoint: ReceiptLedgerCheckpoint) throws {
        if isUnreachable { throw ReceiptLedgerWitnessError.unreachable("test double") }
        if let checkpoint, checkpoint.ledgerHighWaterMark > newCheckpoint.ledgerHighWaterMark {
            throw ReceiptLedgerWitnessError.wouldRegress(
                witnessed: checkpoint.ledgerHighWaterMark,
                offered: newCheckpoint.ledgerHighWaterMark
            )
        }
        checkpoint = newCheckpoint
    }

    public func latestCheckpoint() throws -> ReceiptLedgerCheckpoint? {
        if isUnreachable { throw ReceiptLedgerWitnessError.unreachable("test double") }
        return checkpoint
    }

    /// Plants a checkpoint without going through the append-only guard, so a test can stand in for a
    /// witness that saw a state this device has since destroyed — which is the whole point of having
    /// one, and is unreachable through `publish` from a ledger that no longer holds those rows.
    public func seed(_ newCheckpoint: ReceiptLedgerCheckpoint) {
        checkpoint = newCheckpoint
    }
}
