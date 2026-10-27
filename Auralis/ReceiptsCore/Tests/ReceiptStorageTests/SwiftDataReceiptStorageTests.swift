import CryptoKit
import Foundation
import ReceiptsCore
@testable import ReceiptStorage
import AuralisRuntime
import SwiftData
import Testing

@MainActor
struct SwiftDataReceiptStorageTests {
    @Test("append receipt persists expected stored receipt")
    func appendPersistsStoredReceipt() async throws {
        let context = try makeContext()
        let store = SwiftDataReceiptStore(
            modelContext: context
        )

        let record = try await store.append(makeDraft(kind: "account.added", correlationID: "flow-1"))
        let storedReceipts = try context.fetch(FetchDescriptor<StoredReceipt>())

        #expect(record.sequenceID == 1)
        #expect(storedReceipts.count == 1)
        let storedReceipt = try #require(storedReceipts.first)
        #expect(storedReceipt.trigger == "account.added")
        #expect(storedReceipt.correlationID == "flow-1")
    }

    @Test("fetch and export ordering match receipt timeline behavior")
    func fetchAndExportOrdering() async throws {
        let context = try makeContext()
        let store = SwiftDataReceiptStore(
            modelContext: context
        )

        let first = try await store.append(
            makeDraft(createdAt: Date(timeIntervalSince1970: 100), kind: "first")
        )
        let second = try await store.append(
            makeDraft(createdAt: Date(timeIntervalSince1970: 100), kind: "second")
        )
        let newest = try await store.append(
            makeDraft(createdAt: Date(timeIntervalSince1970: 300), kind: "newest")
        )

        let latest = try await store.latest(limit: 2)
        let exportedRecords = try ReceiptCanonicalJSON.decoder().decode(
            ReceiptProvenanceExport.self,
            from: try await store.exportAll()
        ).records

        #expect(latest.map(\.sequenceID) == [newest.sequenceID, second.sequenceID])
        #expect(exportedRecords.map(\.sequenceID) == [first.sequenceID, second.sequenceID, newest.sequenceID])
    }

    @Test("reset deletes persisted receipts and restarts sequence allocation")
    func resetDeletesPersistedReceipts() async throws {
        let context = try makeContext()
        let store = SwiftDataReceiptStore(
            modelContext: context
        )
        let resetService = SwiftDataReceiptResetService(receiptStore: store)

        _ = try await store.append(makeDraft(kind: "first"))
        _ = try await store.append(makeDraft(kind: "second"))

        try await resetService.resetReceipts()
        let replacement = try await store.append(makeDraft(kind: "replacement"))

        #expect(try context.fetch(FetchDescriptor<StoredReceipt>()).map(\.trigger) == ["replacement"])
        #expect(replacement.sequenceID == 1)
    }

    @Test("append sequence remains monotonic after integrity-head rollback")
    func appendSequenceRemainsMonotonicAfterIntegrityHeadRollback() async throws {
        let context = try makeContext()
        let headStore = FailingOnceReceiptIntegrityHeadStore()
        let store = SwiftDataReceiptStore(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: context.container,
                integrityHeadStore: headStore,
                signer: ReceiptSignerFactory.ephemeralSigner()
            )
        )

        let first = try await store.append(makeDraft(kind: "first"))
        await headStore.failNextSave()

        await #expect(throws: FailingReceiptHeadStoreError.saveFailed) {
            _ = try await store.append(makeDraft(kind: "rolled-back"))
        }
        let second = try await store.append(makeDraft(kind: "second"))

        #expect(first.sequenceID == 1)
        #expect(second.sequenceID == 2)
        #expect(try context.fetch(FetchDescriptor<StoredReceipt>()).map(\.trigger) == ["first", "second"])
    }

    @Test("integrity-head restoration reports failures instead of silently succeeding")
    func integrityHeadRestorationReportsFailures() async throws {
        let context = try makeContext()
        let headStore = FailingOnceReceiptIntegrityHeadStore()
        let persistenceStore = ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: headStore,
            signer: ReceiptSignerFactory.ephemeralSigner()
        )
        await headStore.failNextSave()

        await #expect(throws: ReceiptHeadRestorationError.self) {
            try await persistenceStore.restoreHeads(["account": "hash"])
        }
    }

    /// A partial failure has to be partial: one unwritable anchor must not silently discard the
    /// others, and the error has to name the one that failed. Restoring a single key — which is all
    /// the test above did — cannot distinguish "reported the failure" from "abandoned the batch".
    @Test("a partly-failing head restoration still writes the rest and names what failed")
    func integrityHeadRestorationIsPartialNotAllOrNothing() async throws {
        let context = try makeContext()
        let headStore = FailingKeyReceiptIntegrityHeadStore(failingKey: "account-b")
        let persistenceStore = ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: headStore,
            signer: ReceiptSignerFactory.ephemeralSigner()
        )

        let error = await #expect(throws: ReceiptHeadRestorationError.self) {
            try await persistenceStore.restoreHeads([
                "account-a": "hash-a",
                "account-b": "hash-b",
                "account-c": "hash-c"
            ])
        }

        let failures = try #require(error?.failures)
        #expect(failures.count == 1)
        #expect(failures.first?.hasPrefix("account-b:") == true)
        // The two writable anchors landed regardless of where the failing one fell in iteration order.
        #expect(await headStore.loadAllHeads() == ["account-a": "hash-a", "account-c": "hash-c"])
    }

    @Test("appended receipts are signed and pass signature verification")
    func appendedReceiptsAreSignedAndVerify() async throws {
        let context = try makeContext()
        let persistenceStore = ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
            signer: ReceiptSignerFactory.ephemeralSigner()
        )
        let store = SwiftDataReceiptStore(persistenceStore: persistenceStore)

        let record = try await store.append(makeDraft(kind: "signed"))
        #expect(record.signature != nil)
        #expect(record.signerPublicKey != nil)

        // `.verified` rather than `isValid`: the store holds this signer for its whole lifetime, so
        // a downgrade to `.unattested` here would mean attestation silently stopped working — and
        // `isValid` accepts `.unattested`, which is exactly how that regression would hide.
        let result = try await persistenceStore.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
        #expect(result.isFullyAttested)
    }

    @Test("receipt verification rejects a valid signature from a substituted signer")
    func receiptVerificationRejectsSignerSubstitution() async throws {
        let context = try makeContext()
        let trustedSigner = SoftwareReceiptSigner()
        let persistenceStore = ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
            signer: trustedSigner
        )
        let store = SwiftDataReceiptStore(persistenceStore: persistenceStore)

        _ = try await store.append(makeDraft(kind: "signed"))
        let storedReceipt = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        let attackerSignature = try await SoftwareReceiptSigner().sign(storedReceipt.chainHash)
        storedReceipt.signature = attackerSignature.signature.base64EncodedString()
        storedReceipt.signerPublicKey = attackerSignature.publicKeyRepresentation.base64EncodedString()
        try context.save()

        let result = try await persistenceStore.verifyIntegrity()
        #expect(result.status == .tampered)
        // Caught by the chain hash rather than by an identity comparison: the signer's public key is
        // part of the hashed envelope, so swapping it invalidates the hash the signature is over.
        // That is strictly stronger than the previous "must equal the one current key" rule, which
        // could only reject a *foreign* key and so also rejected this device's own earlier keys
        // after a restore.
        #expect(result.failureReason?.contains("invalid chain hash") == true)
    }

    @Test("a ledger written before signing existed is unattested, not tampered with")
    func legacyUnsignedLedgerIsUnattested() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let persistenceStore = ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: headStore,
            signer: ReceiptSignerFactory.ephemeralSigner()
        )
        let store = SwiftDataReceiptStore(persistenceStore: persistenceStore)

        _ = try await store.append(makeDraft(kind: "legacy"))
        // Exactly the post-migration shape: a new optional column reads back nil on every row that
        // predates it. The chain hash omits the signer when it is nil, so the row stays consistent.
        let storedReceipt = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        storedReceipt.signature = nil
        storedReceipt.signerPublicKey = nil
        storedReceipt.chainHash = try Self.rehash(storedReceipt)
        try context.save()
        try await persistenceStore.restoreHeads([
            Self.accountKey(storedReceipt.accountAddress): storedReceipt.chainHash
        ])

        let result = try await persistenceStore.verifyIntegrity()
        #expect(result.status == .unattested)
        #expect(result.isValid, "an upgraded ledger must not read as tampered with")
        #expect(result.isFullyAttested == false)
        #expect(result.failureReason?.contains("predates receipt signing") == true)

        // The blast radius that made this blocking: export refused forever, leaving deletion as the
        // only recovery.
        let exported = try await persistenceStore.exportAll()
        #expect(exported.isEmpty == false)

        // And the archive has to survive the *external* verifier too, which applies its own copy of
        // the forward-only rule. Asserting only that bytes came out left the verifier's unsigned
        // prefix path and its `.unattested` summary with no coverage at all, so an archive that no
        // third party would accept still passed this test.
        let anchor = try await persistenceStore.provenanceTrustAnchor()
        let verified = try ReceiptProvenanceVerifier.verify(
            exported,
            trustedSignerFingerprint: anchor.fingerprint
        )
        #expect(verified.status == .unattested, "\(verified.failureReason ?? "-")")
        #expect(verified.failureReason?.contains("predates receipt signing") == true)
    }

    @Test("stripping a signature after a signed receipt is tampering")
    func strippingSignatureAfterSignedReceiptIsTampering() async throws {
        let context = try makeContext()
        let persistenceStore = ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
            signer: ReceiptSignerFactory.ephemeralSigner()
        )
        let store = SwiftDataReceiptStore(persistenceStore: persistenceStore)

        _ = try await store.append(makeDraft(kind: "first"))
        _ = try await store.append(makeDraft(kind: "second"))

        // The grandfathering rule is forward-only, so it cannot be used as a bypass: an attacker who
        // removes a signature from a row that follows a signed one is still caught.
        let receipts = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
        )
        let second = try #require(receipts.last)
        second.signature = nil
        second.signerPublicKey = nil
        second.chainHash = try Self.rehash(second)
        try context.save()

        let result = try await persistenceStore.verifyIntegrity()
        #expect(result.status == .tampered)
        #expect(result.isValid == false)
    }

    @Test("a ledger restored without its local anchors is unattested, not tampered with")
    func restoredLedgerWithoutAnchorsIsUnattested() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        // The original device: its own signing identity, and it anchors what it writes.
        let originalStore = SwiftDataReceiptStore(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: context.container,
                integrityHeadStore: headStore,
                signer: ReceiptSignerFactory.ephemeralSigner()
            )
        )
        _ = try await originalStore.append(makeDraft(kind: "restored"))

        // Restoring brings the SwiftData store back but neither the signing key nor the integrity
        // anchors — both are `ThisDeviceOnly`. So the new device has a fresh identity and no heads.
        await headStore.clearAllHeads()
        let restoredStore = ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: headStore,
            signer: ReceiptSignerFactory.ephemeralSigner()
        )

        let result = try await restoredStore.verifyIntegrity()
        #expect(result.status == .unattested)
        #expect(result.isValid, "a restored ledger must not read as tampered with")
        #expect(result.isFullyAttested == false)
        #expect(try await restoredStore.exportAll().isEmpty == false)
    }

    @Test("a restored ledger stays valid after the new device writes to it again")
    func restoredLedgerStaysValidAfterNewWrite() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let originalStore = SwiftDataReceiptStore(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: context.container,
                integrityHeadStore: headStore,
                signer: ReceiptSignerFactory.ephemeralSigner()
            )
        )

        // Two accounts written on the old device, then the anchors are lost in the transfer.
        _ = try await originalStore.append(makeDraft(kind: "old-a", accountAddress: Self.accountA))
        _ = try await originalStore.append(makeDraft(kind: "old-b", accountAddress: Self.accountB))
        await headStore.clearAllHeads()

        // The restored device writes once. That anchors account A but not account B, so an
        // all-or-nothing anchor check would call the ledger tampered — the false positive this covers.
        let restoredPersistenceStore = ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: headStore,
            signer: ReceiptSignerFactory.ephemeralSigner()
        )
        let restoredStore = SwiftDataReceiptStore(
            persistenceStore: restoredPersistenceStore
        )
        _ = try await restoredStore.append(makeDraft(kind: "new-a", accountAddress: Self.accountA))

        let result = try await restoredPersistenceStore.verifyIntegrity()
        #expect(result.status == .unattested)
        #expect(result.isValid, "a restored ledger must not become tampered on the next write")
        #expect(try await restoredPersistenceStore.exportAll().isEmpty == false)
    }

    /// A missing anchor for a chain *this device wrote* is still tampering — the grandfathering above
    /// must not become a way to drop anchors.
    ///
    /// Account A carries **two** receipts, and that is the whole point of the fixture. With only one,
    /// the state is indistinguishable from an append that saved its row and was killed before writing
    /// its first anchor, which is an honest crash window rather than tampering — see
    /// ``genesisAppendCrashWindowIsHealedNotTampering()``. At `accountSequenceID == 2` the previous
    /// append would already have written an anchor, so its absence has no innocent explanation.
    @Test("a missing anchor for a locally written multi-receipt chain is tampering")
    func missingAnchorForLocallyWrittenChainIsTampering() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let persistenceStore = ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: headStore,
            signer: ReceiptSignerFactory.ephemeralSigner()
        )
        let store = SwiftDataReceiptStore(persistenceStore: persistenceStore)

        _ = try await store.append(makeDraft(kind: "a1", accountAddress: Self.accountA))
        _ = try await store.append(makeDraft(kind: "a2", accountAddress: Self.accountA))
        _ = try await store.append(makeDraft(kind: "b", accountAddress: Self.accountB))
        // Drop just one anchor, leaving the other in place: this device demonstrably wrote both.
        await headStore.clearHead(for: Self.accountA.lowercased())

        let result = try await persistenceStore.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(result.isValid == false)
        #expect(result.failureReason?.contains("without protected heads") == true, "\(result.failureReason ?? "-")")
    }

    /// The other side of that bound: an account whose *first and only* receipt has no anchor.
    ///
    /// `performAppend` saves the row and then writes the anchor, so a kill in that window leaves no
    /// anchor at all when the row is the account's genesis — there is no earlier append to have left
    /// one behind. The one-row-behind tolerance covers the same crash at sequence 2 and above and
    /// heals it; this case fell through to `.tampered` instead, which made the very first receipt on
    /// a newly added wallet the one place an interrupted append poisoned the verdict — for the whole
    /// ledger, since the verdict is not per account, and permanently unless that account happened to
    /// receive another receipt.
    ///
    /// `appendCompensationFailed` reaches this shape without a crash, on an account's *genesis* row.
    /// On a later row it lands in the one-row-behind window instead and reads `.unattested` — see
    /// `ReceiptIntegrityVerdictTests.appendCompensationFailureIsReported`, which pins that verdict.
    @Test("a genesis append killed before its anchor write is healed, not called tampering")
    func genesisAppendCrashWindowIsHealedNotTampering() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let persistenceStore = ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: headStore,
            signer: ReceiptSignerFactory.ephemeralSigner()
        )
        let store = SwiftDataReceiptStore(persistenceStore: persistenceStore)

        // Account B exists with its anchor intact, so this is not "no anchors anywhere" — the device
        // demonstrably wrote and anchored other chains.
        _ = try await store.append(makeDraft(kind: "b", accountAddress: Self.accountB))
        let genesis = try await store.append(makeDraft(kind: "a1", accountAddress: Self.accountA))
        #expect(genesis.accountSequenceID == 1)
        await headStore.clearHead(for: Self.accountA.lowercased())

        let result = try await persistenceStore.verifyIntegrity()
        #expect(result.isValid, "a genesis crash window is not tampering: \(result.failureReason ?? "-")")
        #expect(result.failureReason?.contains("without protected heads") != true, "\(result.failureReason ?? "-")")

        // Healed in place rather than left for an append that may never come, which is the same
        // reasoning the one-row-behind window uses.
        #expect(await headStore.loadHead(for: Self.accountA.lowercased()) == genesis.chainHash)
        // And once healed the ledger is fully attested again, so the export a person came for works.
        #expect(try await persistenceStore.verifyIntegrity().status == .verified)
        #expect(try await persistenceStore.exportAll().isEmpty == false)
    }

    private static let accountA = "0x1111111111111111111111111111111111111111"
    private static let accountB = "0x2222222222222222222222222222222222222222"

    /// Recomputes the chain hash for a row whose signing columns were changed, so the test exercises
    /// the signature rules rather than tripping the chain-hash check first.
    private static func rehash(_ receipt: StoredReceipt) throws -> String {
        try ReceiptIntegrity.chainHash(for: receipt)
    }

    /// Forwards to the production derivation rather than restating it.
    ///
    /// This used to reimplement the fold (`nil`/`""` → `"global"`, lowercase otherwise) by hand, so a
    /// change to `ReceiptIntegrity.accountKey` would have left these anchor keys silently pointing at
    /// the old scheme — the tests that pin the anchor invariant would have gone on passing against a
    /// key the store no longer uses. Kept as a shorthand only because the call sites read better.
    private static func accountKey(_ accountAddress: String?) -> String {
        ReceiptIntegrity.accountKey(accountAddress: accountAddress)
    }

    @Test("append fails closed when the receipt signer cannot establish provenance")
    func appendFailsClosedWhenSigningFails() async throws {
        let context = try makeContext()
        let persistenceStore = ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
            signer: FailingReceiptSigner()
        )
        let store = SwiftDataReceiptStore(persistenceStore: persistenceStore)

        await #expect(throws: ReceiptSigningTestError.signingFailed) {
            _ = try await store.append(makeDraft(kind: "must-not-persist"))
        }

        #expect(try context.fetch(FetchDescriptor<StoredReceipt>()).isEmpty)
    }

    /// A signing failure must not consume the sequence ID it allocated. `allocateSequenceID()`
    /// advances a cache before the signer is ever called, so the throw has to release it — otherwise
    /// the next append writes a row with a hole in `sequenceID`, which is the "sequence gap" the
    /// `.tampered` contract names. A locked Keychain makes this the ordinary failure, not an exotic
    /// one, so the gap would accumulate one ID per locked-device write attempt.
    @Test("a failed signing attempt does not consume a sequence ID")
    func failedSigningDoesNotConsumeASequenceID() async throws {
        let context = try makeContext()
        let signer = FailingOnceReceiptSigner()
        let store = SwiftDataReceiptStore(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: context.container,
                integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
                signer: signer
            )
        )

        let first = try await store.append(makeDraft(kind: "first"))
        await signer.failNextSign()

        await #expect(throws: ReceiptSigningTestError.signingFailed) {
            _ = try await store.append(makeDraft(kind: "must-not-persist"))
        }
        let second = try await store.append(makeDraft(kind: "second"))

        #expect(first.sequenceID == 1)
        #expect(second.sequenceID == 2, "the failed attempt burned a sequence ID")
        #expect(try await store.verifyIntegrity().status == .verified)
    }

    /// The append path saves the row and then writes the Keychain anchor. A crash in between leaves
    /// the anchor one row behind, and strict tail equality called that tampering — permanently, for
    /// any account that never receives another receipt. Simulated by rewinding the anchor to the
    /// tip's `previousReceiptHash`, which is exactly the state that window produces.
    @Test("an integrity anchor left one receipt behind by a crash is healed, not called tampering")
    func anchorOneReceiptBehindIsHealed() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = SwiftDataReceiptStore(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: context.container,
                integrityHeadStore: headStore,
                signer: ReceiptSignerFactory.ephemeralSigner()
            )
        )

        _ = try await store.append(makeDraft(kind: "first"))
        let second = try await store.append(makeDraft(kind: "second"))
        let accountKey = Self.accountKey(second.accountAddress)
        await headStore.saveHead(second.previousReceiptHash, for: accountKey)

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "a one-behind anchor was misreported: \(result.failureReason ?? "-")")
        // Healed rather than merely tolerated, so an account that never gets another receipt does not
        // re-enter the same state on every check.
        #expect(await headStore.loadHead(for: accountKey) == second.chainHash)
    }

    /// The tolerance above must not generalize. An anchor two rows back is not the crash window and
    /// must stay tampering, or an attacker could append an unbounded run of rows past a stale anchor.
    @Test("an anchor further back than one receipt is still tampering")
    func anchorTwoReceiptsBehindIsTampering() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = SwiftDataReceiptStore(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: context.container,
                integrityHeadStore: headStore,
                signer: ReceiptSignerFactory.ephemeralSigner()
            )
        )

        let first = try await store.append(makeDraft(kind: "first"))
        _ = try await store.append(makeDraft(kind: "second"))
        let third = try await store.append(makeDraft(kind: "third"))
        await headStore.saveHead(first.chainHash, for: Self.accountKey(third.accountAddress))

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered)
        #expect(result.failureReason?.contains("chain head mismatch") == true)
    }

    /// `detailsData` is `@Attribute(.externalStorage)`, so the blob can go missing with no adversary.
    /// That has to be a verdict, and an **unattested** one.
    ///
    /// This assertion was `.tampered` (F-44). The doc comment above it already said the blob "can go
    /// missing with no adversary" and the test then asserted the ledger had been altered, so the
    /// defect was pinned by the suite rather than caught by it. `.invalid` is `.tampered`, and
    /// `isValid` is false only for `.tampered`, so one pruned blob made `exportAll()` refuse the
    /// whole history permanently — `resetAll()`, destroying it, being the only exit. That is exactly
    /// the consequence F-39 and F-40 were raised as Blockers for, reached by storage pressure.
    ///
    /// The other rows on the ledger keep verifying, which is the half that makes this a per-row
    /// concession rather than a blanket downgrade.
    @Test("an unreadable payload is unattested, not tampering, and does not condemn the other rows")
    func unreadablePayloadIsUnattestedNotTampering() async throws {
        let context = try makeContext()
        let store = SwiftDataReceiptStore(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: context.container,
                integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
                signer: ReceiptSignerFactory.ephemeralSigner()
            )
        )
        _ = try await store.append(makeDraft(kind: "corrupt-me"))
        _ = try await store.append(makeDraft(kind: "intact"))

        let rows = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
        )
        let stored = try #require(rows.first)
        stored.replaceDetailsDataForTesting(Data("not json".utf8))
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .unattested, "\(result.failureReason ?? "-")")
        #expect(result.isValid, "a pruned external-storage blob is not evidence of tampering")
        #expect(result.failureReason?.contains("unreadable payload") == true, "\(result.failureReason ?? "-")")

        // The ledger stays readable, which is the point of the verdict change: the console renders
        // the damaged row with an explicit "unavailable" marker instead of the history disappearing.
        let records = try await store.allRecords()
        #expect(records.count == 2)
        #expect(
            records.contains { $0.details.values[StoredReceipt.unavailablePayloadKey] == .bool(true) },
            "the unreadable row should read back as unavailable, not as having recorded nothing"
        )

        // Export still refuses — deliberately, and this is the explicit half of F-44's decision. An
        // archive cannot carry an empty payload beside the real payload's hash without indicting
        // itself, so it fails with its own stated error type rather than leaking `DecodingError`.
        await #expect(throws: ReceiptProvenanceExportError.self) {
            _ = try await store.exportAll()
        }
    }

    /// The bound on the concession above. Loss is unattested; **substitution is still tampering**.
    ///
    /// Without this, relaxing the decode failure could be over-read into relaxing the payload-hash
    /// comparison itself, which is the check that catches an edited payload. A blob that decodes
    /// cleanly but hashes to something other than its `payloadHash` column has been rewritten, and
    /// that is the one thing this leg exists to detect.
    @Test("a payload that decodes but does not match its recorded hash is still tampering")
    func substitutedPayloadIsStillTampering() async throws {
        let context = try makeContext()
        let store = SwiftDataReceiptStore(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: context.container,
                integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
                signer: ReceiptSignerFactory.ephemeralSigner()
            )
        )
        _ = try await store.append(makeDraft(kind: "substitute-me"))

        let stored = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        // Valid JSON for a *different* payload: it decodes, so the unattested path is not taken.
        stored.replaceDetailsDataForTesting(
            try JSONEncoder().encode(ReceiptPayload(values: ["address": .string("0xsubstituted")]))
        )
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(
            result.failureReason?.contains("invalid payload hash") == true,
            "\(result.failureReason ?? "-")"
        )
    }

    /// Reset deletes rows before clearing anchors, so a failing anchor clear cannot leave rows
    /// stranded without heads — the state that used to brand the ledger tampered forever.
    @Test("a reset whose anchor clear fails leaves no rows behind and recovers on retry")
    func resetSurvivesAFailingAnchorClear() async throws {
        let context = try makeContext()
        let headStore = FailingClearReceiptIntegrityHeadStore()
        let store = SwiftDataReceiptStore(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: context.container,
                integrityHeadStore: headStore,
                signer: ReceiptSignerFactory.ephemeralSigner()
            )
        )
        _ = try await store.append(makeDraft(kind: "first"))
        await headStore.failNextClearAll()

        await #expect(throws: FailingReceiptHeadStoreError.clearFailed) {
            try await store.resetAll()
        }
        // The rows are gone even though the anchor clear threw, so the failure is recoverable rather
        // than a permanent rows-without-heads inconsistency.
        #expect(try context.fetch(FetchDescriptor<StoredReceipt>()).isEmpty)
        #expect(await headStore.loadAllHeads().isEmpty == false)

        // Retrying finishes the job, which is the property that makes the window survivable.
        try await store.resetAll()
        #expect(await headStore.loadAllHeads().isEmpty)
    }

    @Test("reset handles inserted unsaved receipts in the main context")
    func resetHandlesInsertedUnsavedReceipts() async throws {
        let context = try makeContext()
        let resetService = SwiftDataReceiptResetService(
            modelContext: context,
            integrityHeadStoreForTesting: InMemoryReceiptIntegrityHeadStore()
        )
        context.insert(try makeStoredReceipt(sequenceID: 99, kind: "unsaved"))

        try await resetService.resetReceipts()

        #expect(try context.fetch(FetchDescriptor<StoredReceipt>()).isEmpty)
    }

    @Test("receipt event logger sanitizes payloads with moved store")
    func loggerSanitizesThroughMovedStore() async throws {
        let context = try makeContext()
        let store = SwiftDataReceiptStore(
            modelContext: context
        )
        let logger = ReceiptEventLogger(receiptStore: store)

        _ = try await logger.append(
            trigger: "network.failed",
            scope: "networking",
            summary: "Network request failed",
            provenance: "test",
            rawPayload: RawReceiptPayload(
                fields: [
                    .public("url", string: "https://rpc.example/secret", kind: .url),
                    .public("error", string: "provider failed", kind: .errorMessage)
                ]
            ),
            actorDetail: .system,
            authorityDetail: nil
        )

        let receipt = try #require(try await store.latest(limit: 1).first)
        #expect(receipt.details.values["url"] == .string("<redacted-url>"))
        #expect(receipt.details.values["error"] == .string("<redacted-error>"))
    }

    @Test("structured actor detail round-trips through append/export and stays tamper-evident")
    func structuredActorDetailRoundTrips() async throws {
        let context = try makeContext()
        let persistenceStore = ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
            signer: ReceiptSignerFactory.ephemeralSigner()
        )
        let store = SwiftDataReceiptStore(persistenceStore: persistenceStore)

        let detail = ReceiptActorDetail(
            kind: "model",
            identifier: "com.auralis.autopilot",
            displayName: "Autopilot",
            inferenceLocality: "remote",
            inferenceProvider: "anthropic",
            inferenceModelClass: "opus"
        )
        let record = try await store.append(
            ReceiptDraft(
                category: "runtime",
                kind: "tool.executed",
                correlationID: nil,
                payload: ReceiptPayload(values: [:]),
                actorDetail: detail,
                authorityDetail: nil
            )
        )

        #expect(record.actorDetail == detail)
        // Survives the SwiftData column round-trip and the JSON export contract.
        let stored = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        #expect(stored.actorDetail == detail)
        let exported = try ReceiptCanonicalJSON.decoder().decode(
            ReceiptProvenanceExport.self,
            from: try await store.exportAll()
        ).records
        #expect(exported.first?.actorDetail == detail)
        // Attribution is part of the signed chain hash, not just a loose column — asserted by
        // mutating the column and re-deriving, because `verifyIntegrity().isValid` (what this used
        // to check) passes whether or not the field is in the envelope: append and verify call the
        // same function either way, so the fields could be deleted from `ReceiptIntegrityEnvelope`
        // and this test would still have gone green. `isValid` also accepts `.unattested`.
        let baseline = try ReceiptIntegrity.chainHash(for: stored)
        #expect(stored.chainHash == baseline, "the persisted hash must be the one the envelope derives")
        stored.actorInferenceProvider = "someone-else"
        #expect(try ReceiptIntegrity.chainHash(for: stored) != baseline)
        stored.actorInferenceProvider = detail.inferenceProvider
        #expect(try ReceiptIntegrity.chainHash(for: stored) == baseline)
    }

    /// `ReceiptDraft.actorDetail` is required as of P0.5-602, so a *new* receipt can no longer be
    /// written without attribution. The unattributed shape is still reachable at the storage layer —
    /// the columns are optional because `nil` is a real answer for authority — so it is exercised
    /// here directly rather than through a draft that can no longer produce it.
    @Test("a stored receipt with no attribution reads back as unattributed")
    func storedReceiptWithoutActorDetailReadsBackAsNil() async throws {
        let stored = try makeStoredReceipt(sequenceID: 1, kind: "unattributed")

        #expect(stored.actorKindRawValue == nil)

        let record = stored.asReceiptRecord()
        #expect(record.actorDetail == nil)
        #expect(record.authorityDetail == nil)

        // Every optional column has to be *committed to* when populated and *omitted* when nil —
        // otherwise a populated value could be edited without moving the hash.
        //
        // Re-derived from the row rather than compared to itself: `record.chainHash == stored.chainHash`
        // was the fixture's `chainHash` literal on both sides and so could never fail, which meant the
        // claim this test makes was never actually tested.
        let rederived = try ReceiptIntegrity.chainHash(for: stored)
        #expect(rederived.count == 64)

        stored.actorKindRawValue = "human"
        #expect(try ReceiptIntegrity.chainHash(for: stored) != rederived)
        stored.actorKindRawValue = nil
        #expect(try ReceiptIntegrity.chainHash(for: stored) == rederived)

        // Same contract for the signing identity, which is what separates a key rotation from a
        // signer substitution. Carried over from the deleted schema-version suite.
        stored.signerPublicKey = "a-signer-key"
        #expect(try ReceiptIntegrity.chainHash(for: stored) != rederived)
        stored.signerPublicKey = nil
        #expect(try ReceiptIntegrity.chainHash(for: stored) == rederived)
    }

    /// P0.5-601/602 — "under what authority" has to survive persistence and be covered by the signed
    /// chain hash, or an auditor can't trust what the receipt says permitted the action.
    @Test("authority attribution round-trips through columns, export, and the signed chain")
    func authorityDetailRoundTripsAndIsSigned() async throws {
        let context = try makeContext()
        let persistenceStore = ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
            signer: ReceiptSignerFactory.ephemeralSigner()
        )
        let store = SwiftDataReceiptStore(persistenceStore: persistenceStore)
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let authority = ReceiptAuthorityDetail(
            source: "lease",
            leaseID: "6C7E4C3E-1F2B-4E6E-9A4C-2F1B3D5E7A90",
            capability: "playback_queue",
            scope: "execution",
            reason: "Planner may queue playback for 20 minutes.",
            expiresAt: expiry
        )
        let record = try await store.append(
            ReceiptDraft(
                category: "runtime",
                kind: "tool.executed",
                correlationID: nil,
                payload: ReceiptPayload(values: [:]),
                actorDetail: ReceiptActorDetail(kind: "workflow", identifier: "planner"),
                authorityDetail: authority
            )
        )

        #expect(record.authorityDetail == authority)
        let stored = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        #expect(stored.authorityDetail == authority)
        #expect(stored.authorityLeaseID == "6C7E4C3E-1F2B-4E6E-9A4C-2F1B3D5E7A90")
        let exported = try ReceiptCanonicalJSON.decoder().decode(
            ReceiptProvenanceExport.self,
            from: try await store.exportAll()
        ).records
        #expect(exported.first?.authorityDetail == authority)

        // Every authority column, individually. `verifyIntegrity().isValid` (what this used to
        // assert) could not distinguish "in the envelope" from "not in the envelope", so five of
        // these six fields had no coverage at all — a `leaseID` or an `expiresAt` could have been
        // edited on disk without moving the hash and nothing here would have noticed.
        let baseline = try ReceiptIntegrity.chainHash(for: stored)
        #expect(stored.chainHash == baseline)

        stored.authoritySourceRawValue = "policyDefault"
        #expect(try ReceiptIntegrity.chainHash(for: stored) != baseline, "authority source is unhashed")
        stored.authoritySourceRawValue = authority.source

        stored.authorityLeaseID = "00000000-0000-0000-0000-000000000000"
        #expect(try ReceiptIntegrity.chainHash(for: stored) != baseline, "lease id is unhashed")
        stored.authorityLeaseID = authority.leaseID

        stored.authorityCapabilityRawValue = "wallet_signing"
        #expect(try ReceiptIntegrity.chainHash(for: stored) != baseline, "capability is unhashed")
        stored.authorityCapabilityRawValue = authority.capability

        stored.authorityScopeRawValue = "standing"
        #expect(try ReceiptIntegrity.chainHash(for: stored) != baseline, "scope is unhashed")
        stored.authorityScopeRawValue = authority.scope

        stored.authorityReason = "Something else entirely."
        #expect(try ReceiptIntegrity.chainHash(for: stored) != baseline, "reason is unhashed")
        stored.authorityReason = authority.reason

        stored.authorityExpiresAt = expiry.addingTimeInterval(86_400)
        #expect(try ReceiptIntegrity.chainHash(for: stored) != baseline, "expiry is unhashed")
        stored.authorityExpiresAt = authority.expiresAt

        // Back to the original values, so the loop above proves sensitivity rather than corruption.
        #expect(try ReceiptIntegrity.chainHash(for: stored) == baseline)
    }

    /// The remaining envelope fields that carry governance meaning. Same gap as the authority
    /// columns: nothing asserted that editing them on disk moves the hash.
    @Test("the chain hash commits to sequence, linkage, and outcome")
    func chainHashCommitsToCoreLedgerFields() async throws {
        let context = try makeContext()
        let store = SwiftDataReceiptStore(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: context.container,
                integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
                signer: ReceiptSignerFactory.ephemeralSigner()
            )
        )
        _ = try await store.append(makeDraft(kind: "core-fields"))
        let stored = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        let baseline = try ReceiptIntegrity.chainHash(for: stored)

        stored.accountSequenceID += 1
        #expect(try ReceiptIntegrity.chainHash(for: stored) != baseline, "accountSequenceID is unhashed")
        stored.accountSequenceID -= 1

        stored.previousReceiptHash = "GENESIS-TAMPERED"
        #expect(try ReceiptIntegrity.chainHash(for: stored) != baseline, "previousReceiptHash is unhashed")
        stored.previousReceiptHash = ReceiptIntegrity.genesisHash

        stored.isSuccess.toggle()
        #expect(try ReceiptIntegrity.chainHash(for: stored) != baseline, "isSuccess is unhashed")
        stored.isSuccess.toggle()

        stored.sequenceID += 1
        #expect(try ReceiptIntegrity.chainHash(for: stored) != baseline, "sequenceID is unhashed")
        stored.sequenceID -= 1

        #expect(try ReceiptIntegrity.chainHash(for: stored) == baseline)
    }

    @Test("trust anchor can be pinned independently before a provenance export")
    func trustAnchorMatchesLaterExport() async throws {
        let context = try makeContext()
        let store = SwiftDataReceiptStore(
            modelContext: context
        )

        let independentlyPinnedAnchor = try await store.provenanceTrustAnchor()
        _ = try await store.append(makeDraft(kind: "account.added"))
        let export = try ReceiptCanonicalJSON.decoder().decode(
            ReceiptProvenanceExport.self,
            from: try await store.exportAll()
        )

        #expect(export.trustAnchor == independentlyPinnedAnchor)
        let verification = try ReceiptProvenanceVerifier.verify(
            try await store.exportAll(),
            trustedSignerFingerprint: independentlyPinnedAnchor.fingerprint
        )
        #expect(verification.isValid)
    }

    @Test("export verification rejects receipt keys that differ from the pinned manifest signer")
    func exportVerificationRejectsMixedSignerIdentity() async throws {
        let context = try makeContext()
        let trustedSigner = SoftwareReceiptSigner()
        let store = SwiftDataReceiptStore(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: context.container,
                integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
                signer: trustedSigner
            )
        )
        let pinnedAnchor = try await store.provenanceTrustAnchor()
        _ = try await store.append(makeDraft(kind: "account.added"))
        let originalExport = try ReceiptCanonicalJSON.decoder().decode(
            ReceiptProvenanceExport.self,
            from: try await store.exportAll()
        )
        let originalRecord = try #require(originalExport.records.first)
        let attackerSignature = try await SoftwareReceiptSigner().sign(originalRecord.chainHash)
        let substitutedRecord = replacingSignature(
            on: originalRecord,
            signature: attackerSignature.signature.base64EncodedString(),
            signerPublicKey: attackerSignature.publicKeyRepresentation.base64EncodedString()
        )
        let manifest = ReceiptProvenanceManifest(
            recordCount: 1,
            recordsHash: testSHA256Hex(
                try testCanonicalData([substitutedRecord])
            ),
            chainHeads: originalExport.manifest.chainHeads
        )
        let manifestHash = testSHA256Hex(try testCanonicalData(manifest))
        let manifestSignature = try await trustedSigner.sign(manifestHash)
        let substitutedExport = ReceiptProvenanceExport(
            records: [substitutedRecord],
            manifest: manifest,
            manifestHash: manifestHash,
            manifestSignature: manifestSignature.signature.base64EncodedString(),
            trustAnchor: pinnedAnchor
        )

        let result = try ReceiptProvenanceVerifier.verify(
            try testCanonicalData(substitutedExport),
            trustedSignerFingerprint: pinnedAnchor.fingerprint
        )
        // Pinned to *which* check rejects it. Swapping `signerPublicKey` without rederiving the chain
        // hash is caught by the integrity recomputation, not by the identity comparison — so asserting
        // only `isValid == false` let this pass without the identity rule ever running. The rule
        // itself is covered by the two tests below.
        #expect(result.status == .tampered)
        #expect(result.failureReason?.contains("invalid exported integrity metadata") == true)
    }

    /// The identity rule the test above never reached: a record that is *correctly* signed, by a key
    /// that is not the pinned export identity.
    ///
    /// The distinction matters because the verdict is `.unattested`, whose `isValid` is `true` — the
    /// opposite of what a `isValid == false` assertion would have claimed. This is the ordinary
    /// device-restore shape, and calling it tampering is what left restored installs unable to export
    /// their own history.
    @Test("a record signed by a non-pinned identity verifies as unattested, not tampered")
    func exportVerificationTreatsAForeignSignerAsUnattested() async throws {
        let context = try makeContext()
        let trustedSigner = SoftwareReceiptSigner()
        let store = SwiftDataReceiptStore(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: context.container,
                integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
                signer: trustedSigner
            )
        )
        let pinnedAnchor = try await store.provenanceTrustAnchor()
        _ = try await store.append(makeDraft(kind: "account.added"))
        let originalExport = try ReceiptCanonicalJSON.decoder().decode(
            ReceiptProvenanceExport.self,
            from: try await store.exportAll()
        )
        let originalRecord = try #require(originalExport.records.first)

        // A previous device identity, done properly: the row is rebuilt so its chain hash commits to
        // the other key, and the signature is over that hash. Nothing here is inconsistent — it just
        // was not signed by the identity the verifier was told to trust.
        let previousSigner = SoftwareReceiptSigner()
        let previousKey = try await previousSigner.publicKeyRepresentation().base64EncodedString()
        let rederivedChainHash = try testChainHash(for: originalRecord, signerPublicKey: previousKey)
        let previousSignature = try await previousSigner.sign(rederivedChainHash)
        let foreignRecord = replacingIntegrity(
            on: originalRecord,
            chainHash: rederivedChainHash,
            signature: previousSignature.signature.base64EncodedString(),
            signerPublicKey: previousKey
        )
        let export = try await makeExport(
            records: [foreignRecord],
            signedBy: trustedSigner,
            trustAnchor: pinnedAnchor
        )

        let result = try ReceiptProvenanceVerifier.verify(
            export,
            trustedSignerFingerprint: pinnedAnchor.fingerprint
        )
        #expect(result.status == .unattested, "\(result.failureReason ?? "-")")
        #expect(result.isValid, "a previous device identity is not tampering")
        #expect(result.isFullyAttested == false)
        #expect(result.failureReason?.contains("not signed by the pinned export identity") == true)
    }

    /// The forward-only half of the same rule: reverting to a previous identity *after* the pinned one
    /// has signed is the one arrangement of these parts that is genuinely tampering, and it is what
    /// stops the `.unattested` allowance from being a bypass.
    @Test("reverting to a previous identity after the pinned one is tampering")
    func exportVerificationRejectsIdentityRegression() async throws {
        let context = try makeContext()
        let trustedSigner = SoftwareReceiptSigner()
        let store = SwiftDataReceiptStore(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: context.container,
                integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
                signer: trustedSigner
            )
        )
        let pinnedAnchor = try await store.provenanceTrustAnchor()
        _ = try await store.append(makeDraft(kind: "first"))
        _ = try await store.append(makeDraft(kind: "second"))
        let originalExport = try ReceiptCanonicalJSON.decoder().decode(
            ReceiptProvenanceExport.self,
            from: try await store.exportAll()
        )
        #expect(originalExport.records.count == 2)
        let secondRecord = try #require(originalExport.records.last)

        let previousSigner = SoftwareReceiptSigner()
        let previousKey = try await previousSigner.publicKeyRepresentation().base64EncodedString()
        let rederivedChainHash = try testChainHash(for: secondRecord, signerPublicKey: previousKey)
        let previousSignature = try await previousSigner.sign(rederivedChainHash)
        let regressedRecord = replacingIntegrity(
            on: secondRecord,
            chainHash: rederivedChainHash,
            signature: previousSignature.signature.base64EncodedString(),
            signerPublicKey: previousKey
        )
        let records = [try #require(originalExport.records.first), regressedRecord]
        let export = try await makeExport(
            records: records,
            signedBy: trustedSigner,
            trustAnchor: pinnedAnchor,
            chainHeads: [
                ReceiptProvenanceChainHead(
                    accountKey: Self.accountKey(regressedRecord.accountAddress),
                    accountSequenceID: regressedRecord.accountSequenceID,
                    chainHash: regressedRecord.chainHash
                )
            ]
        )

        let result = try ReceiptProvenanceVerifier.verify(
            export,
            trustedSignerFingerprint: pinnedAnchor.fingerprint
        )
        #expect(result.status == .tampered)
        #expect(result.failureReason?.contains("reverts to a previous signing identity") == true)
    }

    @Test("an export naming an unknown format or algorithm is refused outright")
    func exportVerificationRejectsUnsupportedFormat() async throws {
        let context = try makeContext()
        let store = SwiftDataReceiptStore(modelContext: context)
        _ = try await store.append(makeDraft(kind: "account.added"))
        let anchor = try await store.provenanceTrustAnchor()
        let original = try ReceiptCanonicalJSON.decoder().decode(
            ReceiptProvenanceExport.self,
            from: try await store.exportAll()
        )

        // Refused, not reported as tampered: this verifier has no idea what these bytes mean, which
        // is a different answer from "I understood them and they are wrong".
        for mutation in Self.unsupportedFormatMutations(of: original) {
            #expect(throws: ReceiptProvenanceExportError.unsupportedFormat) {
                _ = try ReceiptProvenanceVerifier.verify(
                    try testCanonicalData(mutation),
                    trustedSignerFingerprint: anchor.fingerprint
                )
            }
        }
    }

    @Test("a manifest whose record count disagrees with its records is tampering")
    func exportVerificationRejectsManifestRecordCountMismatch() async throws {
        let context = try makeContext()
        let trustedSigner = SoftwareReceiptSigner()
        let store = SwiftDataReceiptStore(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: context.container,
                integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
                signer: trustedSigner
            )
        )
        let anchor = try await store.provenanceTrustAnchor()
        _ = try await store.append(makeDraft(kind: "account.added"))
        let original = try ReceiptCanonicalJSON.decoder().decode(
            ReceiptProvenanceExport.self,
            from: try await store.exportAll()
        )

        // The count is what tells a verifier how many receipts to expect, so it is the field an
        // attacker edits after dropping rows. Signed correctly and self-consistent everywhere else.
        let manifest = ReceiptProvenanceManifest(
            recordCount: original.records.count + 1,
            recordsHash: original.manifest.recordsHash,
            chainHeads: original.manifest.chainHeads
        )
        let manifestHash = testSHA256Hex(try testCanonicalData(manifest))
        let manifestSignature = try await trustedSigner.sign(manifestHash)
        let export = ReceiptProvenanceExport(
            records: original.records,
            manifest: manifest,
            manifestHash: manifestHash,
            manifestSignature: manifestSignature.signature.base64EncodedString(),
            trustAnchor: anchor
        )

        let result = try ReceiptProvenanceVerifier.verify(
            try testCanonicalData(export),
            trustedSignerFingerprint: anchor.fingerprint
        )
        #expect(result.status == .tampered)
        #expect(result.failureReason?.contains("does not match its manifest") == true)
    }

    private static func unsupportedFormatMutations(
        of export: ReceiptProvenanceExport
    ) -> [ReceiptProvenanceExport] {
        [
            ReceiptProvenanceExport(
                format: "com.attacker.receipts",
                records: export.records,
                manifest: export.manifest,
                manifestHash: export.manifestHash,
                manifestSignature: export.manifestSignature,
                trustAnchor: export.trustAnchor
            ),
            ReceiptProvenanceExport(
                version: ReceiptProvenanceExport.currentVersion + 1,
                records: export.records,
                manifest: export.manifest,
                manifestHash: export.manifestHash,
                manifestSignature: export.manifestSignature,
                trustAnchor: export.trustAnchor
            ),
            ReceiptProvenanceExport(
                records: export.records,
                manifest: export.manifest,
                manifestHash: export.manifestHash,
                manifestSignature: export.manifestSignature,
                trustAnchor: ReceiptProvenanceTrustAnchor(
                    algorithm: "RSA-1024/MD5",
                    publicKey: export.trustAnchor.publicKey,
                    fingerprint: export.trustAnchor.fingerprint
                )
            )
        ]
    }
}

@MainActor
private func makeContext() throws -> ModelContext {
    try ReceiptStorageTestModelContainers.context()
}

private func makeDraft(
    createdAt: Date = Date(timeIntervalSince1970: 100),
    kind: String,
    correlationID: String? = nil,
    accountAddress: String? = nil
) -> ReceiptDraft {
    ReceiptDraft(
        createdAt: createdAt,
        category: "accounts",
        kind: kind,
        correlationID: correlationID,
        payload: ReceiptPayload(
            values: ["address": .string(accountAddress ?? "0xabc")]
        ),
        actorDetail: .system,
        authorityDetail: nil
    )
}

private func makeStoredReceipt(
    sequenceID: Int,
    kind: String
) throws -> StoredReceipt {
    try StoredReceipt(
        sequenceID: sequenceID,
        createdAt: Date(timeIntervalSince1970: 100),
        actor: .system,
        mode: .observe,
        trigger: kind,
        scope: "accounts",
        summary: "Fixture",
        provenance: "test",
        isSuccess: true,
        correlationID: nil,
        timelineAccountAddress: nil,
        timelineChainRawValue: nil,
        accountSequenceID: sequenceID,
        payloadHash: "payload-hash-\(sequenceID)",
        previousReceiptHash: "previous-hash-\(sequenceID)",
        chainHash: "chain-hash-\(sequenceID)",
        details: ReceiptPayload(values: [:])
    )
}

private func replacingSignature(
    on record: ReceiptRecord,
    signature: String,
    signerPublicKey: String
) -> ReceiptRecord {
    ReceiptRecord(
        id: record.id,
        sequenceID: record.sequenceID,
        createdAt: record.createdAt,
        actor: record.actor,
        actorDetail: record.actorDetail,
        authorityDetail: record.authorityDetail,
        mode: record.mode,
        trigger: record.trigger,
        scope: record.scope,
        summary: record.summary,
        provenance: record.provenance,
        isSuccess: record.isSuccess,
        correlationID: record.correlationID,
        accountAddress: record.accountAddress,
        chainRawValue: record.chainRawValue,
        accountSequenceID: record.accountSequenceID,
        payloadHash: record.payloadHash,
        previousReceiptHash: record.previousReceiptHash,
        chainHash: record.chainHash,
        signature: signature,
        signerPublicKey: signerPublicKey,
        details: record.details
    )
}

/// Deliberately the *production* canonical encoder rather than a hand-rolled copy of it.
///
/// A local copy is how this drifted: it sorted keys but left dates at `JSONEncoder`'s default, so a
/// hand-built export encoded `createdAt` in a different time base than the verifier decodes. Every
/// `recordsHash` mismatched, and tests asserting only `isValid == false` passed for that reason
/// instead of the one they were named for.
private func replacingIntegrity(
    on record: ReceiptRecord,
    chainHash: String,
    signature: String,
    signerPublicKey: String
) -> ReceiptRecord {
    ReceiptRecord(
        id: record.id,
        sequenceID: record.sequenceID,
        createdAt: record.createdAt,
        actor: record.actor,
        actorDetail: record.actorDetail,
        authorityDetail: record.authorityDetail,
        mode: record.mode,
        trigger: record.trigger,
        scope: record.scope,
        summary: record.summary,
        provenance: record.provenance,
        isSuccess: record.isSuccess,
        correlationID: record.correlationID,
        accountAddress: record.accountAddress,
        chainRawValue: record.chainRawValue,
        accountSequenceID: record.accountSequenceID,
        payloadHash: record.payloadHash,
        previousReceiptHash: record.previousReceiptHash,
        chainHash: chainHash,
        signature: signature,
        signerPublicKey: signerPublicKey,
        // Carried over, not defaulted. Dropping it silently relabels the record as
        // `ReceiptIntegrityEnvelopeVersion.legacy`, so the verifier rebuilds the *older* envelope and
        // every one of these tests fails on "invalid exported integrity metadata" before it reaches
        // the signing rule it was written for — the same way a hand-rolled canonical encoder used to
        // make them pass for the wrong reason.
        integrityEnvelopeVersion: record.integrityEnvelopeVersion,
        details: record.details
    )
}

/// The chain hash this record *should* carry under a different signing key, derived through the
/// production envelope so a hand-built export stays internally consistent.
///
/// Needed because the signer's public key is inside the hashed envelope: a test that swaps the key
/// without rederiving this produces a row that fails the integrity recomputation, and so never
/// reaches the identity rule it meant to exercise.
private func testChainHash(for record: ReceiptRecord, signerPublicKey: String?) throws -> String {
    try ReceiptIntegrity.chainHash(
        receiptID: record.id,
        envelopeVersion: record.integrityEnvelopeVersion ?? ReceiptIntegrityEnvelopeVersion.legacy,
        sequenceID: record.sequenceID,
        accountSequenceID: record.accountSequenceID,
        createdAt: record.createdAt,
        actorRawValue: record.actor.rawValue,
        actorColumns: ReceiptActorColumns(record.actorDetail),
        authorityColumns: ReceiptAuthorityColumns(record.authorityDetail),
        contributionColumns: record.contributionColumns,
        modeRawValue: record.mode.rawValue,
        trigger: record.trigger,
        scope: record.scope,
        summary: record.summary,
        provenance: record.provenance,
        isSuccess: record.isSuccess,
        correlationID: record.correlationID,
        accountAddress: record.accountAddress,
        chainRawValue: record.chainRawValue,
        payloadHash: record.payloadHash,
        signerPublicKey: signerPublicKey,
        previousReceiptHash: record.previousReceiptHash
    )
}

/// Rebuilds a complete, correctly signed export around a mutated record set, so a test can isolate
/// *one* broken property instead of tripping the manifest checks on the way to it.
private func makeExport(
    records: [ReceiptRecord],
    signedBy signer: SoftwareReceiptSigner,
    trustAnchor: ReceiptProvenanceTrustAnchor,
    chainHeads: [ReceiptProvenanceChainHead]? = nil
) async throws -> Data {
    let heads = chainHeads ?? Dictionary(
        grouping: records,
        by: { ReceiptIntegrity.accountKey(accountAddress: $0.accountAddress) }
    ).compactMap { accountKey, grouped -> ReceiptProvenanceChainHead? in
        guard let head = grouped.max(by: { $0.accountSequenceID < $1.accountSequenceID }) else {
            return nil
        }
        return ReceiptProvenanceChainHead(
            accountKey: accountKey,
            accountSequenceID: head.accountSequenceID,
            chainHash: head.chainHash
        )
    }.sorted { $0.accountKey < $1.accountKey }

    let manifest = ReceiptProvenanceManifest(
        recordCount: records.count,
        recordsHash: testSHA256Hex(try testCanonicalData(records)),
        chainHeads: heads
    )
    let manifestHash = testSHA256Hex(try testCanonicalData(manifest))
    let manifestSignature = try await signer.sign(manifestHash)
    return try testCanonicalData(
        ReceiptProvenanceExport(
            records: records,
            manifest: manifest,
            manifestHash: manifestHash,
            manifestSignature: manifestSignature.signature.base64EncodedString(),
            trustAnchor: trustAnchor
        )
    )
}

private func testCanonicalData<Value: Encodable>(_ value: Value) throws -> Data {
    try ReceiptCanonicalJSON.encoder().encode(value)
}

private func testSHA256Hex(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

private enum FailingReceiptHeadStoreError: Error {
    case saveFailed
    case clearFailed
}

/// Fails `clearAllHeads()` on demand, so the reset ordering can be tested: the rows must already be
/// gone when the anchor clear throws.
private actor FailingClearReceiptIntegrityHeadStore: ReceiptIntegrityHeadStoring {
    private var heads: [String: String] = [:]
    private var ledgerHighWaterMark: Int?
    private var highestEnvelopeVersion: Int?
    private var shouldFailNextClearAll = false

    func failNextClearAll() {
        shouldFailNextClearAll = true
    }

    func loadHead(for accountKey: String) -> String? {
        heads[accountKey]
    }

    func loadAllHeads() -> [String: String] {
        heads
    }

    func saveHead(_ hash: String, for accountKey: String) {
        heads[accountKey] = hash
    }

    func clearHead(for accountKey: String) {
        heads[accountKey] = nil
    }

    func clearAllHeads() throws {
        if shouldFailNextClearAll {
            shouldFailNextClearAll = false
            throw FailingReceiptHeadStoreError.clearFailed
        }
        heads.removeAll()
        ledgerHighWaterMark = nil
        highestEnvelopeVersion = nil
    }

    func loadLedgerHighWaterMark() -> Int? {
        ledgerHighWaterMark
    }

    func saveLedgerHighWaterMark(_ sequenceID: Int) {
        ledgerHighWaterMark = max(ledgerHighWaterMark ?? 0, sequenceID)
    }

    func loadHighestEnvelopeVersion() -> Int? {
        highestEnvelopeVersion
    }

    func saveHighestEnvelopeVersion(_ version: Int) {
        highestEnvelopeVersion = max(highestEnvelopeVersion ?? 0, version)
    }
}

/// Fails `saveHead` for one nominated key and succeeds for every other, so a partial restoration is
/// observable.
private actor FailingKeyReceiptIntegrityHeadStore: ReceiptIntegrityHeadStoring {
    private let failingKey: String
    private var heads: [String: String] = [:]
    private var ledgerHighWaterMark: Int?
    private var highestEnvelopeVersion: Int?

    init(failingKey: String) {
        self.failingKey = failingKey
    }

    func loadHead(for accountKey: String) -> String? {
        heads[accountKey]
    }

    func loadAllHeads() -> [String: String] {
        heads
    }

    func saveHead(_ hash: String, for accountKey: String) throws {
        guard accountKey != failingKey else {
            throw FailingReceiptHeadStoreError.saveFailed
        }
        heads[accountKey] = hash
    }

    func clearHead(for accountKey: String) {
        heads[accountKey] = nil
    }

    func clearAllHeads() {
        heads.removeAll()
        ledgerHighWaterMark = nil
        highestEnvelopeVersion = nil
    }

    func loadLedgerHighWaterMark() -> Int? {
        ledgerHighWaterMark
    }

    func saveLedgerHighWaterMark(_ sequenceID: Int) {
        ledgerHighWaterMark = max(ledgerHighWaterMark ?? 0, sequenceID)
    }

    func loadHighestEnvelopeVersion() -> Int? {
        highestEnvelopeVersion
    }

    func saveHighestEnvelopeVersion(_ version: Int) {
        highestEnvelopeVersion = max(highestEnvelopeVersion ?? 0, version)
    }
}

private enum ReceiptSigningTestError: Error {
    case signingFailed
}

/// Signs normally until armed, so a failed append can be followed by a successful one.
private actor FailingOnceReceiptSigner: ReceiptSigning {
    private let inner = SoftwareReceiptSigner()
    private var shouldFailNextSign = false

    func failNextSign() {
        shouldFailNextSign = true
    }

    func sign(_ message: String) async throws -> ReceiptSignature {
        if shouldFailNextSign {
            shouldFailNextSign = false
            throw ReceiptSigningTestError.signingFailed
        }
        return try await inner.sign(message)
    }

    func publicKeyRepresentation() async throws -> Data {
        try await inner.publicKeyRepresentation()
    }

    nonisolated func verify(_ message: String, signature: ReceiptSignature) -> Bool {
        SoftwareReceiptSigner.verifyStatic(message, signature: signature)
    }
}

private struct FailingReceiptSigner: ReceiptSigning {
    func sign(_ message: String) async throws -> ReceiptSignature {
        throw ReceiptSigningTestError.signingFailed
    }

    func publicKeyRepresentation() async throws -> Data {
        throw ReceiptSigningTestError.signingFailed
    }

    func verify(_ message: String, signature: ReceiptSignature) -> Bool {
        false
    }
}

private actor FailingOnceReceiptIntegrityHeadStore: ReceiptIntegrityHeadStoring {
    private var heads: [String: String] = [:]
    private var ledgerHighWaterMark: Int?
    private var highestEnvelopeVersion: Int?
    private var shouldFailNextSave = false

    func failNextSave() {
        shouldFailNextSave = true
    }

    func loadHead(for accountKey: String) -> String? {
        heads[accountKey]
    }

    func loadAllHeads() -> [String: String] {
        heads
    }

    func saveHead(_ hash: String, for accountKey: String) throws {
        if shouldFailNextSave {
            shouldFailNextSave = false
            throw FailingReceiptHeadStoreError.saveFailed
        }
        heads[accountKey] = hash
    }

    func clearHead(for accountKey: String) {
        heads.removeValue(forKey: accountKey)
    }

    func clearAllHeads() {
        heads.removeAll()
        ledgerHighWaterMark = nil
        highestEnvelopeVersion = nil
    }

    func loadLedgerHighWaterMark() -> Int? {
        ledgerHighWaterMark
    }

    func saveLedgerHighWaterMark(_ sequenceID: Int) {
        ledgerHighWaterMark = max(ledgerHighWaterMark ?? 0, sequenceID)
    }

    func loadHighestEnvelopeVersion() -> Int? {
        highestEnvelopeVersion
    }

    func saveHighestEnvelopeVersion(_ version: Int) {
        highestEnvelopeVersion = max(highestEnvelopeVersion ?? 0, version)
    }
}
