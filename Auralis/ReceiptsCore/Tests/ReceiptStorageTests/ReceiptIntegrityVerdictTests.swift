import Foundation
import ReceiptsCore
@testable import ReceiptStorage
import RuntimeCore
import SwiftData
import Testing

/// The boundaries between the three verdicts, and the places they were drawn in the wrong place.
///
/// `ReceiptIntegrityVerificationResult.Status` exists because collapsing "this device cannot vouch for
/// these rows" into "these rows have been altered" costs the person their audit trail:
/// `exportAll()` refuses on `.tampered`, so a misplaced boundary means the only recovery on offer is
/// destroying the history they were trying to export. Each case here is a state that an honest device
/// reaches on its own and that used to land on the wrong side of one of those lines.
@MainActor
struct ReceiptIntegrityVerdictTests {
    private static let accountA = "0x1111111111111111111111111111111111111111"

    // MARK: - A Keychain that will not answer a read

    /// A locked Keychain has to produce a *verdict*, not unwind the call.
    ///
    /// `performVerifyIntegrity()` deliberately reads the signer identity with `try?` — the comment
    /// there explains that a locked Keychain or a restored device leaves this device with no identity
    /// to compare against, which is unattestable rather than invalid, and that throwing would
    /// propagate out of `exportAll()` as an outright failure. It then read the anchors two dozen lines
    /// later with a plain `try`, and both reads hit the same Keychain.
    ///
    /// So in the exact scenario the `try?` exists for, `loadAllHeads()` threw
    /// `errSecInteractionNotAllowed`, the whole call unwound, and `exportAll()` failed with a raw
    /// `ReceiptIntegrityHeadStoreError` instead of `ReceiptProvenanceExportError` — a caller matching
    /// the documented error type saw nothing, and the graceful path below was unreachable whenever the
    /// cause was a real locked Keychain rather than a test double.
    @Test("a Keychain that cannot be read yields an unattested verdict, not a thrown error")
    func unreadableAnchorsAreUnattestedNotAThrow() async throws {
        let context = try makeContext()
        // Writes succeed first, so the rows and anchors are the ones a working device wrote.
        let headStore = FailingLoadAllReceiptIntegrityHeadStore(isFailingFromTheStart: false)
        let store = try makeStore(context: context, headStore: headStore)

        _ = try await store.append(draft(kind: "first"))
        _ = try await store.append(draft(kind: "second"))

        // Now the device locks.
        await headStore.startFailing()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .unattested, "\(result.failureReason ?? "-")")
        #expect(result.isValid, "a device that cannot read its own anchors has not found tampering")
        #expect(
            result.failureReason?.contains("cannot read its integrity anchors") == true,
            "\(result.failureReason ?? "-")"
        )

        // The completeness advisory has to survive this exit too, and this is the exit where it
        // matters most rather than a consistency nicety. The two settled verdicts below attach it; this
        // early `.unattested` return did not — and a locked `ThisDeviceOnly` Keychain takes the *mark*
        // read down with the anchor read, so the one exit that dropped the note was the one reached
        // exactly when the note is true. A person was told the anchors were unreadable and never told
        // that nothing could vouch for the ledger's completeness either.
        #expect(
            result.completenessAdvisory?.contains("carries no high-water mark") == true,
            "\(result.completenessAdvisory ?? "-")"
        )

        // And the consequence that made this worth fixing: the export still runs. The rows have
        // passed every structural and signature check, and the archive carries its own manifest
        // signature, so a Keychain this device cannot read is no reason to withhold the history.
        let exported = try await store.exportAll()
        let decoded = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: exported)
        #expect(decoded.records.count == 2)
    }

    // MARK: - The crash window after a signing-identity rotation

    /// The one-row anchor tolerance must not be gated on the signer being *unavailable*.
    ///
    /// It was: the fallback required `!hasSignerIdentity`, justified by "`currentIdentitySeen` is
    /// empty whenever the signer could not produce a key at all — a locked Keychain, most likely".
    /// That premise is false. The set is also empty when the signer answers perfectly well but no row
    /// was signed by *that* key, which is precisely what this package's own key rotation produces
    /// (`DeviceReceiptSigner.secureEnclaveSigner()` writing off an unrestorable Enclave blob).
    ///
    /// So: crash between the row save and the anchor write, then rotate. The anchors live under a
    /// different Keychain service and survive untouched, the ledger sits in the ordinary crash window,
    /// and the verdict was `.tampered` — durably, for any account that never receives another receipt,
    /// which is the exact outcome the healing exists to prevent.
    @Test("a crash-window anchor is unattested, not tampering, after the signing identity rotates")
    func crashWindowAfterIdentityRotationIsUnattested() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = RotatingSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        _ = try await store.append(draft(kind: "first"))
        let second = try await store.append(draft(kind: "second"))
        // The anchor exactly one row behind the tip: what a crash between the row save and the anchor
        // write leaves behind.
        let accountKey = ReceiptIntegrity.accountKey(accountAddress: Self.accountA)
        await headStore.saveHead(second.previousReceiptHash, for: accountKey)

        // The Enclave blob will not restore, so the device rotates onto a new identity. It can still
        // sign and still name its key — it simply signed none of the rows above.
        await signer.rotate()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .unattested, "\(result.failureReason ?? "-")")
        #expect(result.isValid, "a rotated identity is not evidence of tampering")
        #expect(result.failureReason?.contains("head mismatch") == false, "\(result.failureReason ?? "-")")

        // The anchor is left where it was rather than healed: healing asserts "this device wrote the
        // newer row", and after a rotation this device cannot say that.
        #expect(await headStore.loadHead(for: accountKey) == second.previousReceiptHash)
    }

    /// The bound that keeps the tolerance above from being a hole. Dropping the `!hasSignerIdentity`
    /// conjunct widened what counts as the crash window, so the *depth* limit is now the only thing
    /// standing between a stale anchor and an unbounded run of forged rows.
    @Test("an anchor more than one receipt behind is still tampering after a rotation")
    func deepAnchorRewindAfterRotationIsStillTampering() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = RotatingSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        let first = try await store.append(draft(kind: "first"))
        _ = try await store.append(draft(kind: "second"))
        _ = try await store.append(draft(kind: "third"))
        await headStore.saveHead(
            first.chainHash,
            for: ReceiptIntegrity.accountKey(accountAddress: Self.accountA)
        )
        await signer.rotate()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(result.failureReason?.contains("head mismatch") == true, "\(result.failureReason ?? "-")")
    }

    // MARK: - The store and the bundled verifier must agree

    /// An empty-string signature classified differently on the two sides of the export boundary.
    ///
    /// The store treated the signing columns as the legitimate unsigned prefix when they were `nil`
    /// **or empty**; `ReceiptProvenanceVerifier` tested only for `nil`, and `Data(base64Encoded: "")`
    /// returns non-`nil` empty `Data`. So the row sailed past the verifier's guard into
    /// `verifyStatic`, where a P-256 key built from no bytes throws and the answer comes back `false`.
    ///
    /// The result was the worst available shape: the local check called the ledger `.unattested`,
    /// `isValid` let it export, and the verifier shipped alongside that archive called the very same
    /// row `.tampered`. An honest ledger marked forged at the one boundary where it matters.
    @Test("empty signing columns get the same verdict from the store and the export verifier")
    func emptySigningColumnsAgreeAcrossBothVerifiers() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)
        let anchor = try await store.provenanceTrustAnchor()

        _ = try await store.append(draft(kind: "empty-signature"))

        // Blanked rather than removed, which is the shape the two sides disagreed about.
        let stored = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        stored.signature = ""
        stored.signerPublicKey = ""
        // The signer key is inside the hashed envelope, so the chain hash has to be recomputed or the
        // chain-hash check fires first and this never reaches the signing rules. The anchor moves with
        // it for the same reason.
        stored.chainHash = try ReceiptIntegrity.chainHash(for: stored)
        try context.save()
        await headStore.saveHead(
            stored.chainHash,
            for: ReceiptIntegrity.accountKey(accountAddress: Self.accountA)
        )

        let local = try await store.verifyIntegrity()
        #expect(local.status == .unattested, "\(local.failureReason ?? "-")")

        // The assertion that matters: the same row, through the verifier a third party would run.
        let verified = try ReceiptProvenanceVerifier.verify(
            try await store.exportAll(),
            trustedSignerFingerprint: anchor.fingerprint
        )
        #expect(
            verified.status == local.status,
            "the store said \(local.status) and the bundled verifier said \(verified.status): \(verified.failureReason ?? "-")"
        )
    }

    /// The other half of the same divergence. A signature that is *present but not base64* was
    /// `.invalid` in the store and was swallowed into the verifier's "predates receipt signing"
    /// branch — reported to a third party as an honest unsigned prefix.
    @Test("a malformed signature is tampering in the store and in the export verifier alike")
    func malformedSigningColumnsAgreeAcrossBothVerifiers() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        _ = try await store.append(draft(kind: "malformed-signature"))

        let stored = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        stored.signature = "not%%base64%%at%%all"
        stored.chainHash = try ReceiptIntegrity.chainHash(for: stored)
        try context.save()
        await headStore.saveHead(
            stored.chainHash,
            for: ReceiptIntegrity.accountKey(accountAddress: Self.accountA)
        )

        let local = try await store.verifyIntegrity()
        #expect(local.status == .tampered, "\(local.failureReason ?? "-")")
        // Not exportable, so the verifier cannot be asked directly — which is the correct end state:
        // the divergence is gone because the store now refuses to produce the archive at all.
        await #expect(throws: ReceiptProvenanceExportError.self) {
            _ = try await store.exportAll()
        }
    }

    /// The classification itself, since it is now the single definition both sides read.
    @Test("signing-metadata classification requires the two columns to be both present or both absent")
    func signingMetadataClassification() {
        let signed = Data("signature".utf8).base64EncodedString()
        let key = Data("key".utf8).base64EncodedString()

        // **Both absent** is the only unsigned shape. This test previously asserted the opposite for
        // the half-present cases below — that either column alone folded to `.unsigned` — and that was
        // the widest hole in the package rather than a harmless leniency: `signerPublicKey` is inside
        // the hashed envelope and `signature` cannot be, so clearing only the signature left every
        // chain hash verifying while demoting an attested row to "predates receipt signing". See
        // ``ReceiptSigningMetadata/classify(signature:signerPublicKey:)`` for what that then unlocked.
        #expect(ReceiptSigningMetadata.classify(signature: nil, signerPublicKey: nil) == .unsigned)
        // Empty is still folded in with nil — the case the two verifiers once disagreed about, because
        // `Data(base64Encoded: "")` succeeds and would otherwise reach signature verification.
        #expect(ReceiptSigningMetadata.classify(signature: "", signerPublicKey: "") == .unsigned)
        #expect(ReceiptSigningMetadata.classify(signature: nil, signerPublicKey: "") == .unsigned)

        // Half-present in either direction is tampering, at any position on any account.
        #expect(ReceiptSigningMetadata.classify(signature: nil, signerPublicKey: key) == .halfSigned)
        #expect(ReceiptSigningMetadata.classify(signature: signed, signerPublicKey: nil) == .halfSigned)
        #expect(ReceiptSigningMetadata.classify(signature: signed, signerPublicKey: "") == .halfSigned)
        #expect(ReceiptSigningMetadata.classify(signature: "", signerPublicKey: key) == .halfSigned)

        #expect(ReceiptSigningMetadata.classify(signature: "%%%", signerPublicKey: key) == .malformed)
        #expect(ReceiptSigningMetadata.classify(signature: signed, signerPublicKey: "%%%") == .malformed)

        guard case let .signed(signature, publicKey) = ReceiptSigningMetadata.classify(
            signature: signed,
            signerPublicKey: key
        ) else {
            Issue.record("a well-formed pair did not classify as signed")
            return
        }
        #expect(signature == Data("signature".utf8))
        #expect(publicKey == Data("key".utf8))
    }

    // MARK: - Ledger-wide completeness

    /// Duplicate sequence IDs, which is what the original concurrency defect actually produced —
    /// `append` read the ledger, awaited the signature, and two callers minted the same ID. The gap
    /// reporter has a branch for it that nothing exercised.
    @Test("duplicate sequence numbers are reported, not just gaps")
    func duplicateSequenceIDsAreReported() {
        #expect(ReceiptIntegrity.sequenceGapReasons(sequenceIDs: [1, 2, 3]).isEmpty)

        let duplicated = ReceiptIntegrity.sequenceGapReasons(sequenceIDs: [1, 2, 2, 3])
        #expect(duplicated.isEmpty == false, "a duplicated sequence number went unreported")
        #expect(
            duplicated.contains { $0.localizedCaseInsensitiveContains("duplicate") },
            "\(duplicated)"
        )

        // A duplicate also makes the count right while the set is short, so a naive
        // count-versus-range check would have passed here.
        #expect(ReceiptIntegrity.sequenceGapReasons(sequenceIDs: [1, 1]).isEmpty == false)
    }

    // MARK: - The ledger lock

    /// A locked body that throws has to release the queue.
    ///
    /// Every ledger mutation waits on the previous one, so a failure that left the tail unfinished
    /// would hang every later append in the process — and a hang is the worst thing to diagnose from a
    /// field report, which is why non-reentrancy is asserted rather than merely documented.
    @Test("a failed locked operation releases the ledger queue")
    func aFailedLockedOperationReleasesTheQueue() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())

        _ = try await store.append(draft(kind: "first"))

        // Corrupting the payload makes `exportAll()` throw from inside the lock.
        let stored = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        stored.replaceDetailsDataForTesting(Data("not-json".utf8))
        try context.save()
        await #expect(throws: ReceiptProvenanceExportError.self) {
            _ = try await store.exportAll()
        }

        // The queue moved on. Before the tail dropped a failed predecessor this awaited forever.
        let second = try await store.append(draft(kind: "second"))
        #expect(second.sequenceID == 2)
    }

    // MARK: - The degraded-consistency error

    /// `appendCompensationFailed` is the one error this package documents as *degraded receipt
    /// integrity* — the head-store write failed and the compensating row delete failed too, so the
    /// database and the anchors may no longer agree. It had no coverage of any kind.
    ///
    /// Only the message is asserted, and the reason is worth stating rather than hiding: reaching the
    /// real path needs a `ModelContext` whose `save()` throws while the container is otherwise
    /// healthy, which an in-memory `ModelContainer` will not do and which is not worth a production
    /// seam to fake. What *is* worth pinning is that both underlying causes survive into the message,
    /// because this error's only job is to tell a person and a log why the ledger is degraded — and an
    /// enum case that drops one of its two payloads would do that silently.
    @Test("the degraded-consistency error names both failures that produced it")
    func appendCompensationFailureNamesBothCauses() {
        let error = ReceiptPersistenceConsistencyError.appendCompensationFailed(
            headStoreError: "keychain interaction not allowed",
            receiptRollbackError: "disk is full"
        )

        let described = error.errorDescription ?? ""
        #expect(described.contains("keychain interaction not allowed"), "\(described)")
        #expect(described.contains("disk is full"), "\(described)")
    }

    /// The real path: the anchor write fails *and* the compensating row delete fails too.
    ///
    /// This is the one outcome the package documents as degraded integrity, and it had no coverage
    /// because reaching it needs a `ModelContext` whose `save()` throws while the container is
    /// otherwise healthy. `setCompensationFailureForTesting` is a `DEBUG`-only seam added for exactly
    /// this, because the end state matters: a row is on disk with no anchor, and if its
    /// `accountSequenceID` is above 1 that reads `.tampered` for the whole ledger from then on.
    @Test("an append whose anchor write and rollback both fail reports degraded consistency")
    func appendCompensationFailureIsReported() async throws {
        let context = try makeContext()
        let headStore = FailingLoadAllReceiptIntegrityHeadStore(isFailingFromTheStart: false)
        let store = try makeStore(context: context, headStore: headStore)

        // A first receipt so the account is established and anchored normally.
        _ = try await store.append(draft(kind: "first"))

        // Now both halves of the append's failure handling break: the anchor write throws, and so
        // does the delete that would undo the row.
        await headStore.startFailingSaves()
        await store.setCompensationFailureForTesting(CompensationFailure.diskFull)

        let thrown = await #expect(throws: ReceiptPersistenceConsistencyError.self) {
            _ = try await store.append(draft(kind: "doomed"))
        }

        // Not the raw head-store error: the caller has to be able to tell "this append failed" from
        // "the database and the anchors may no longer agree".
        guard case let .appendCompensationFailed(headStoreError, rollbackError) = try #require(thrown) else {
            Issue.record("expected appendCompensationFailed")
            return
        }
        #expect(headStoreError.isEmpty == false)
        #expect(rollbackError.isEmpty == false)

        // And the state the error is warning about is real: the row survived without an anchor.
        await store.setCompensationFailureForTesting(nil)
        await headStore.stopFailing()
        let rows = try context.fetch(FetchDescriptor<StoredReceipt>())
        #expect(rows.count == 2, "the doomed row was rolled back after all, so the error was wrong")

        // The verdict that state actually produces, pinned rather than left to prose.
        //
        // `.unattested`, **not** `.tampered`, and the difference matters enough to assert: several
        // comments in this package described this state as reading `.tampered` for the whole ledger
        // from then on. It does not. The compensating delete failed, so the row is still there and
        // the anchor still names its immediate parent — which is exactly the one-row crash window the
        // anchor check already tolerates and tries to heal. The heal then fails too (the head store
        // is still refusing writes), and that is reported as an unattested reason rather than a
        // verdict.
        //
        // So the ledger stays exportable, which is the right outcome and the whole point of the
        // trichotomy: the rows have passed every structural and signature check, and a Keychain that
        // will not take a write is no reason to withhold a person's history. Asserting it keeps the
        // claim honest and makes a regression to `.tampered` visible.
        let degraded = try await store.verifyIntegrity()
        #expect(degraded.status == .unattested, "\(degraded.failureReason ?? "-")")
        #expect(degraded.isValid, "a stale anchor this device could not advance is not tampering")
        #expect(
            degraded.failureReason?.contains("could not be advanced") == true,
            "\(degraded.failureReason ?? "-")"
        )
    }

    private enum CompensationFailure: Error {
        case diskFull
    }

    // MARK: - Export when the signer cannot answer

    /// `exportAll()` must not leak a raw signer error either.
    ///
    /// `performVerifyIntegrity()` tolerates a signer that cannot produce its key so an
    /// honest-but-unattestable ledger stays exportable — and then `performExportAll()` signed the
    /// manifest with a plain `try`, which was the last un-wrapped throw on the path. A transient
    /// Enclave decline during a user-initiated export therefore surfaced as `CryptoKitError` rather
    /// than `ReceiptProvenanceExportError`, so a caller matching the documented type saw nothing.
    @Test("an export refused by an unavailable signer fails as an export error, not a raw signer error")
    func exportWithUnavailableSignerIsATypedExportFailure() async throws {
        let context = try makeContext()
        let signer = RevocableSigner()
        let store = try makeStore(
            context: context,
            headStore: InMemoryReceiptIntegrityHeadStore(),
            signer: signer
        )

        _ = try await store.append(draft(kind: "first"))
        await signer.revoke()

        // Verification still produces a verdict rather than throwing — the ledger is intact, just
        // unattestable from here — so the export gets as far as signing its manifest and fails there.
        #expect(try await store.verifyIntegrity().isValid)
        await #expect(throws: ReceiptProvenanceExportError.self) {
            _ = try await store.exportAll()
        }
    }

    // MARK: - The forward-only rule across accounts

    /// The unsigned-prefix rule is per account, and every other test of it uses a single account.
    ///
    /// An upgraded install has one unsigned prefix per account, and the anchor selection is also per
    /// account — so a ledger that is unsigned on one chain and fully signed on another is the shape
    /// where those two interact. Collapsing them would either brand the signed account unattestable
    /// or let a stripped signature on the unsigned one pass.
    @Test("an unsigned prefix on one account does not taint a fully signed second account")
    func unsignedPrefixIsScopedToItsOwnAccount() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)
        let accountB = "0x2222222222222222222222222222222222222222"

        _ = try await store.append(draft(kind: "a1"))
        _ = try await store.append(draft(kind: "b1", account: accountB))

        // Strip the signature from account A's only row, leaving B's intact.
        let rows = try context.fetch(FetchDescriptor<StoredReceipt>())
        let rowA = try #require(rows.first { $0.accountKey == ReceiptIntegrity.accountKey(accountAddress: Self.accountA) })
        rowA.signature = nil
        rowA.signerPublicKey = nil
        rowA.chainHash = try ReceiptIntegrity.chainHash(for: rowA)
        try context.save()
        await headStore.saveHead(
            rowA.chainHash,
            for: ReceiptIntegrity.accountKey(accountAddress: Self.accountA)
        )

        let result = try await store.verifyIntegrity()
        // Unattested, not tampered: an unsigned genesis row is the legitimate pre-signing shape.
        #expect(result.status == .unattested, "\(result.failureReason ?? "-")")
        #expect(result.failureReason?.contains("predates receipt signing") == true, "\(result.failureReason ?? "-")")

        // Account B's anchor was not disturbed by A's unattested state — the per-account selection
        // held, rather than one account's missing identity suppressing the other's anchor check.
        #expect(await headStore.loadHead(for: ReceiptIntegrity.accountKey(accountAddress: accountB)) != nil)

        // And stripping a signature *after* a signed row on the same account is still tampering, so
        // the per-account scoping did not weaken the rule itself.
        //
        // The *later* row is stripped, not the earlier one, and the distinction is what makes this
        // assertion mean anything. Stripping account B's first row and re-hashing it — which is what
        // this test used to do — changes the hash that B's second row links to, so the verdict came
        // from `"invalid previous hash"` at the chain check and the signing rule was never reached;
        // worse, a first row *is* a legitimate unsigned prefix per account, so the fixture asserted
        // the opposite of its comment and passed with both signing rules deleted. Stripping the tip
        // leaves the chain intact, so a regression is the only thing left to find.
        _ = try await store.append(draft(kind: "b2", account: accountB))
        let accountBKey = ReceiptIntegrity.accountKey(accountAddress: accountB)
        let rowB2 = try #require(
            try context.fetch(
                FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
            ).last { $0.accountKey == accountBKey }
        )
        #expect(rowB2.accountSequenceID == 2, "the fixture must strip the tip, not the genesis row")
        rowB2.signature = nil
        rowB2.signerPublicKey = nil
        rowB2.chainHash = try ReceiptIntegrity.chainHash(for: rowB2)
        try context.save()
        await headStore.saveHead(rowB2.chainHash, for: accountBKey)

        let afterStrip = try await store.verifyIntegrity()
        #expect(afterStrip.status == .tampered, "\(afterStrip.failureReason ?? "-")")
        // The reason, not just the status: this has to be the signing rule firing, not a broken chain.
        #expect(
            afterStrip.failureReason?.contains("missing signing metadata after a signed receipt") == true,
            "\(afterStrip.failureReason ?? "-")"
        )
    }

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        try ReceiptStorageTestModelContainers.context()
    }

    private func makeStore(
        context: ModelContext,
        headStore: any ReceiptIntegrityHeadStoring,
        signer: any ReceiptSigning = SoftwareReceiptSigner()
    ) throws -> ReceiptPersistenceStore {
        ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: headStore,
            signer: signer
        )
    }

    private func draft(kind: String, account: String? = nil) -> ReceiptDraft {
        ReceiptDraft(
            createdAt: Date(timeIntervalSince1970: 100),
            actorDetail: .system,
            authorityDetail: nil,
            trigger: kind,
            scope: "accounts",
            summary: "Fixture",
            provenance: "test",
            isSuccess: true,
            correlationID: nil,
            timelineAccountAddress: account ?? Self.accountA,
            timelineChainRawValue: nil,
            details: ReceiptPayload(values: [:])
        )
    }
}
