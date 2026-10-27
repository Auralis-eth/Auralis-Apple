import CloudKit
import Foundation
import OSLog

/// The external witness, backed by the person's **private** CloudKit database.
///
/// Chosen over the alternatives for what it is and is not. It is off-device, so the attacker this
/// package is drawn against — one who can write the SwiftData store — cannot rewrite what it already
/// accepted. It is private to one iCloud account, so unlike a public chain it does not publish the
/// timing and volume of somebody's audit trail to the world. And it needs no service to be built and
/// run, so the witness exists now rather than after a backend does.
///
/// What it is not: a *third-party* witness. Apple holds it, the account owner can delete the zone, and
/// an attacker who has the person's iCloud credentials as well as their device can reach it. It raises
/// the bar from "write one file" to "write one file *and* compromise an iCloud account", which is the
/// whole of the gap that six review rounds kept finding holes in — but a ledger that must survive the
/// account owner themselves needs a notary or a published chain, and this is not that.
///
/// **Append-only is enforced here**, in ``publish(_:)``, not assumed. CloudKit will happily let a
/// client overwrite its own record, so the protocol's central promise has to be kept in this code: a
/// checkpoint that would move the witnessed sequence backwards is refused.
public actor CloudKitReceiptLedgerWitness: ReceiptLedgerWitnessing {
    /// The zone is per-ledger rather than per-record so the whole witness can be located, and read,
    /// in one place — and so a future `resetAll()` integration has something to delete.
    public static let zoneName = "AuralisReceiptLedgerWitness"
    public static let recordType = "ReceiptLedgerCheckpoint"
    /// One record, updated forward. A record *per* checkpoint would be a fuller transparency log, but
    /// the properties checked against a checkpoint are monotonic, so the latest implies the rest —
    /// see ``ReceiptLedgerWitnessing/latestCheckpoint()``.
    public static let recordName = "current"

    private static let logger = Logger(subsystem: "Auralis", category: "CloudKitReceiptLedgerWitness")

    private let container: CKContainer
    private let zoneID: CKRecordZone.ID
    private var didEnsureZone = false

    /// - Parameter containerIdentifier: **Required, and deliberately without a default.**
    ///
    ///   `CKContainer.default()` does not fail — it raises an Objective-C `CKException`
    ///   (*"containerIdentifier can not be nil"*) whenever the process has no iCloud container
    ///   configured, and an `NSException` is not catchable from Swift. As a defaulted argument it was
    ///   evaluated while building the shared receipt store, so a build without the entitlement
    ///   provisioned did not degrade to "no witness" — it **aborted the process**. Measured: `SIGABRT`
    ///   out of `ReceiptStores.persistenceStore(for:)`, which in a shipped app is a launch crash and
    ///   in the test bundle took the whole suite down.
    ///
    ///   Naming the container explicitly keeps every failure inside CloudKit's *error* channel, where
    ///   it can be caught, mapped to ``ReceiptLedgerWitnessError/unreachable(_:)`` and reported as an
    ///   advisory. Nothing in this type touches CloudKit until an operation is actually attempted.
    public init(containerIdentifier: String) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    private var database: CKDatabase {
        container.privateCloudDatabase
    }

    public func publish(_ checkpoint: ReceiptLedgerCheckpoint) async throws {
        // Read-then-write, and the read is what enforces append-only. There is no suspension-free way
        // to do this against a network store, so two devices publishing at once can interleave — which
        // is why the comparison is written to tolerate a *stale* witness (it only ever fires on a
        // backwards move) rather than to require the freshest one.
        if let existing = try await fetchCheckpoint(),
           existing.ledgerHighWaterMark > checkpoint.ledgerHighWaterMark {
            throw ReceiptLedgerWitnessError.wouldRegress(
                witnessed: existing.ledgerHighWaterMark,
                offered: checkpoint.ledgerHighWaterMark
            )
        }

        try await ensureZone()

        let record = CKRecord(
            recordType: Self.recordType,
            recordID: CKRecord.ID(recordName: Self.recordName, zoneID: zoneID)
        )
        record["payload"] = try ReceiptIntegrity.canonicalData(checkpoint) as NSData
        // Kept as a queryable column as well as inside the payload, so an operator looking at the
        // zone can see how far the ledger got without decoding anything.
        record["ledgerHighWaterMark"] = checkpoint.ledgerHighWaterMark as NSNumber

        do {
            // `.changedKeys` rather than `.ifServerRecordUnchanged`: this record is written from one
            // device at a time in the normal case, and a save that fails on an etag conflict would
            // leave the ledger unwitnessed for the sake of a conflict the comparison already
            // tolerates.
            _ = try await database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .changedKeys,
                atomically: true
            )
        } catch {
            throw Self.mapped(error)
        }
    }

    public func latestCheckpoint() async throws -> ReceiptLedgerCheckpoint? {
        try await fetchCheckpoint()
    }

    private func fetchCheckpoint() async throws -> ReceiptLedgerCheckpoint? {
        do {
            let record = try await database.record(
                for: CKRecord.ID(recordName: Self.recordName, zoneID: zoneID)
            )
            guard let payload = record["payload"] as? Data else {
                // A record with no readable payload is not a statement about the ledger, so it must
                // not be reported as one. Treated as "no record", which lands on the advisory.
                Self.logger.error("Receipt witness record carried no decodable payload.")
                return nil
            }
            return try ReceiptCanonicalJSON.decoder().decode(
                ReceiptLedgerCheckpoint.self,
                from: payload
            )
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            // Never witnessed. Genuinely different from "cannot reach the witness", and the
            // difference is reported to the person, so it is returned rather than thrown.
            return nil
        } catch {
            throw Self.mapped(error)
        }
    }

    private func ensureZone() async throws {
        guard !didEnsureZone else { return }
        do {
            _ = try await database.modifyRecordZones(
                saving: [CKRecordZone(zoneID: zoneID)],
                deleting: []
            )
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Already there, which is the outcome this wanted.
        } catch {
            throw Self.mapped(error)
        }
        // Only after the zone really exists, so a failure is retried rather than latched past.
        didEnsureZone = true
    }

    /// Everything CloudKit can fail with collapses to ``ReceiptLedgerWitnessError/unreachable(_:)``,
    /// because for this package's purposes they are one condition: nobody can be asked right now.
    /// Signed out, no network, no entitlement, throttled, quota — none of them is evidence about the
    /// receipts, and all of them must degrade to an advisory rather than accuse an honest ledger.
    private static func mapped(_ error: Error) -> ReceiptLedgerWitnessError {
        if let witnessError = error as? ReceiptLedgerWitnessError {
            return witnessError
        }
        return .unreachable(error.localizedDescription)
    }
}
