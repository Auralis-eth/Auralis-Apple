import Foundation
@testable import AuralisReceipts
import AuralisRuntime
import SwiftData
import Testing

/// The checks that cover *what the ledger does not say* — a chain value resolved from two different
/// places, two account spellings that collide onto one key, a whole account gone, and a verify that
/// races the writes it is verifying. Each of these produced a verdict that was confidently wrong in
/// one direction or the other.
@MainActor
struct ReceiptIntegrityCompletenessTests {
    private static let accountA = "0x1111111111111111111111111111111111111111"
    private static let accountB = "0x2222222222222222222222222222222222222222"

    // MARK: - Resolution divergence

    /// The chain value has to be resolved once, like the account address already is.
    ///
    /// `append` hashed the draft's raw `timelineChainRawValue` while `StoredReceipt` stored
    /// `timelineChainRawValue ?? details.timelineChainRawValue`, so this draft — no explicit chain, a
    /// recognized `chain` in the payload — hashed `nil` and stored `"eth-mainnet"`. `verifyIntegrity()`
    /// re-hashes the row, so it reported `.tampered("invalid chain hash")` for this receipt and every
    /// later one on its account, permanently, with `resetAll()` as the only exit.
    @Test("a chain carried only in the payload still verifies")
    func payloadOnlyChainStillVerifies() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        let record = try await store.append(
            draft(
                kind: "token.transfer",
                payload: [
                    "address": .string(Self.accountA),
                    "chain": .string("eth-mainnet")
                ],
                chainRawValue: nil
            )
        )

        // Stored, not dropped: the payload is where this value legitimately lives for a caller that
        // does not set the column.
        #expect(record.chainRawValue == "eth-mainnet")

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
        #expect(result.isFullyAttested)
    }

    /// The same divergence for the account address, kept as a regression guard alongside the chain
    /// case so the pair cannot drift apart again.
    @Test("an account and a chain resolved from different sources still agree with the hash")
    func mixedResolutionSourcesAgreeWithTheHash() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())

        // Address from the column (checksummed, so it also exercises normalization), chain from the
        // payload. Neither side of the hash may read a different string than the row stores.
        _ = try await store.append(
            draft(
                kind: "token.transfer",
                payload: ["chain": .string("base-mainnet")],
                accountAddress: "0x1111111111111111111111111111111111111111".uppercased(),
                chainRawValue: nil
            )
        )

        let stored = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        #expect(stored.chainRawValue == "base-mainnet")
        #expect(stored.chainHash == (try ReceiptIntegrity.chainHash(for: stored)))
        #expect(try await store.verifyIntegrity().status == .verified)
    }

    // MARK: - Account-key collisions

    /// Two spellings that fold onto one account key must share one chain.
    ///
    /// The append path picked its predecessor by predicating on `accountAddress`, while everything
    /// else grouped by the derived key — and the key folds `nil` and `""` into `"global"`. So a draft
    /// carrying the literal address `"global"` got its own chain starting at `accountSequenceID == 1`
    /// off the genesis hash, `verifyIntegrity()` merged it with the `nil` chain, and the ledger read
    /// `.tampered("invalid account sequence")` from then on.
    @Test("the literal address 'global' does not fork the unattributed chain")
    func literalGlobalAddressDoesNotForkTheUnattributedChain() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())

        _ = try await store.append(draft(kind: "unattributed", payload: [:], accountAddress: nil))
        _ = try await store.append(draft(kind: "literal-global", payload: [:], accountAddress: "global"))
        _ = try await store.append(draft(kind: "unattributed-again", payload: [:], accountAddress: nil))

        let stored = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
        )
        #expect(stored.map(\.accountKey) == ["global", "global", "global"])
        // One chain, so the sequence runs 1, 2, 3 rather than restarting.
        #expect(stored.map(\.accountSequenceID) == [1, 2, 3])

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
    }

    @Test("two spellings of one address share a single chain")
    func caseVariantAddressesShareOneChain() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())

        _ = try await store.append(draft(kind: "lower", payload: [:], accountAddress: Self.accountA))
        _ = try await store.append(
            draft(kind: "upper", payload: [:], accountAddress: "0x1111111111111111111111111111111111111111".uppercased())
        )

        let stored = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
        )
        #expect(stored.map(\.accountSequenceID) == [1, 2])
        #expect(try await store.verifyIntegrity().status == .verified)
    }

    // MARK: - The accountKey migration

    /// A row written before the `accountKey` column existed — the case the whole migration is for,
    /// and the one that had no coverage while the fix was a read-time fallback.
    ///
    /// The fallback derived the key on read but the append path still had to *predicate* on
    /// something, and a `#Predicate` cannot fold `nil`/`""` into `"global"` or lowercase. So it
    /// matched legacy rows by raw address equality and missed exactly the rows the fold exists for:
    /// a pre-column row stored under the literal address `"global"` matched no predecessor, the next
    /// unattributed append restarted at `accountSequenceID == 1`, and `verifyIntegrity()` grouped the
    /// two together and reported `.tampered` permanently — the bug the column was added to remove,
    /// reintroduced by its own compatibility shim.
    @Test("a pre-column row is backfilled and keeps its chain")
    func preColumnRowIsBackfilledAndKeepsItsChain() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        // Written normally, then aged back into the pre-column shape.
        _ = try await store.append(draft(kind: "legacy", payload: [:], accountAddress: "global"))
        let legacyRow = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        #expect(legacyRow.accountKey == "global")
        legacyRow.accountKey = ""
        try context.save()

        // A fresh store, so the backfill has not run for this ledger yet — the same position the app
        // is in on the launch after the column lands.
        let upgraded = try makeStore(context: context, headStore: headStore, signer: signer)
        _ = try await upgraded.append(draft(kind: "after-upgrade", payload: [:], accountAddress: nil))

        let rows = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
        )
        // Backfilled, and folded onto the same key as the unattributed append that followed it.
        #expect(rows.map(\.accountKey) == ["global", "global"])
        // One chain: the new row chained off the legacy one instead of restarting at the genesis hash.
        #expect(rows.map(\.accountSequenceID) == [1, 2])
        #expect(rows.last?.previousReceiptHash == rows.first?.chainHash)

        let result = try await upgraded.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
    }

    /// The backfill must not touch anything the chain hash commits to, or it would invalidate every
    /// row it migrated.
    @Test("the accountKey backfill changes no hashed field")
    func backfillPreservesEveryHashedField() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        _ = try await store.append(draft(kind: "legacy", payload: [:], accountAddress: Self.accountA))
        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        let originalChainHash = row.chainHash
        let originalAddress = row.accountAddress
        row.accountKey = ""
        try context.save()

        _ = try await makeStore(context: context, headStore: headStore, signer: signer).verifyIntegrity()

        // Re-fetched, not the object captured above: the backfill runs on the persistence store's own
        // `ModelContext`, so the row this test holds is a stale snapshot of the same record.
        let migrated = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        #expect(migrated.accountKey == Self.accountA.lowercased())
        #expect(migrated.accountAddress == originalAddress)
        #expect(migrated.chainHash == originalChainHash)
        #expect(migrated.chainHash == (try ReceiptIntegrity.chainHash(for: migrated)))
    }

    /// `accountKey` is the one grouping input outside the hashed envelope, so it is checked against
    /// the column that is inside it. Editing it cannot forge a signature, but it can move a row onto
    /// another account's chain, and that must not be the one part of a row nobody verifies.
    @Test("an edited account key is tampering")
    func editedAccountKeyIsTampering() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())

        _ = try await store.append(draft(kind: "row", payload: [:], accountAddress: Self.accountA))
        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        // Not the empty default, which is the migration case, but a different non-empty key — so the
        // backfill leaves it alone and only the derivation check can catch it.
        row.accountKey = Self.accountB.lowercased()
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered)
        #expect(result.failureReason?.contains("invalid account key") == true, "\(result.failureReason ?? "-")")
    }

    // MARK: - Completeness

    /// Excising an entire account must not read as a verified, fully attested ledger.
    ///
    /// Every other check here is per account — chain linkage, `accountSequenceID`, signatures,
    /// anchors — so deleting all of one account's rows together with its anchor left nothing to
    /// notice: the survivors still linked, no anchor was orphaned, and the verdict was `.verified`
    /// with `isFullyAttested == true`. The ledger asserted it was complete while a wallet's whole
    /// history was gone, which is worse than the threat model admits to.
    ///
    /// Unattested rather than tampered is the deliberate verdict: a hole in the global sequence means
    /// rows are missing but not why, and older builds could leave an identical hole by burning an ID
    /// on a failed signature.
    @Test("deleting an entire account's history is no longer reported as verified")
    func excisingAnAccountIsNotReportedAsVerified() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        for index in 0..<2 {
            _ = try await store.append(draft(kind: "a-\(index)", payload: [:], accountAddress: Self.accountA))
            _ = try await store.append(draft(kind: "b-\(index)", payload: [:], accountAddress: Self.accountB))
        }
        #expect(try await store.verifyIntegrity().status == .verified)

        // The attack: account B's rows *and* its Keychain anchor, so nothing is left dangling.
        let victimRows = try context.fetch(FetchDescriptor<StoredReceipt>())
            .filter { $0.accountKey == Self.accountB.lowercased() }
        #expect(victimRows.count == 2)
        for row in victimRows {
            context.delete(row)
        }
        try context.save()
        await headStore.clearHead(for: Self.accountB.lowercased())

        let result = try await store.verifyIntegrity()
        #expect(result.isFullyAttested == false, "an incomplete ledger must not claim full attestation")
        #expect(result.status == .unattested, "\(result.failureReason ?? "-")")
        // "1 of 3", not "2 of 4", and the discrepancy is the point of this fixture.
        //
        // The accounts are written *interleaved* (`a-0, b-0, a-1, b-1`), so excising B removes
        // sequence 2 and 4 and leaves `[1, 3]` — an interior hole, visible in the rows themselves.
        // That is the row-derived half of completeness, which measures against the highest
        // *surviving* ID: the deleted tail row `b-1` is not in the total, so it undercounts.
        //
        // It undercounts rather than missing it, which is what matters here — the verdict is still
        // `.unattested`. A *sequential* deletion leaves no hole at all and only the high-water mark
        // can see it; that case is in `ReceiptLedgerTruncationTests` and reads `.verified` with an
        // advisory, because the mark is deliberately not verdict-affecting.
        #expect(result.failureReason?.contains("missing 1 of 3") == true, "\(result.failureReason ?? "-")")
    }

    /// An interior gap, where the count is exact: the excised rows are not the most recent, so the
    /// high-water mark survives and the message can say precisely how many receipts are unaccounted
    /// for.
    @Test("an interior run of deleted receipts is counted exactly")
    func interiorSequenceGapIsCountedExactly() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        for index in 0..<2 {
            _ = try await store.append(draft(kind: "a-\(index)", payload: [:], accountAddress: Self.accountA))
            _ = try await store.append(draft(kind: "b-\(index)", payload: [:], accountAddress: Self.accountB))
        }
        // One more on A, so A keeps the highest sequence ID after B is excised.
        _ = try await store.append(draft(kind: "a-last", payload: [:], accountAddress: Self.accountA))

        let victimRows = try context.fetch(FetchDescriptor<StoredReceipt>())
            .filter { $0.accountKey == Self.accountB.lowercased() }
        for row in victimRows {
            context.delete(row)
        }
        try context.save()
        await headStore.clearHead(for: Self.accountB.lowercased())

        let result = try await store.verifyIntegrity()
        #expect(result.status == .unattested, "\(result.failureReason ?? "-")")
        #expect(result.failureReason?.contains("missing 2 of 5") == true, "\(result.failureReason ?? "-")")
    }

    @Test("a ledger with every receipt present reports no sequence gap")
    func intactLedgerReportsNoSequenceGap() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())

        for index in 0..<4 {
            _ = try await store.append(draft(kind: "row-\(index)", payload: [:], accountAddress: Self.accountA))
        }

        // The completeness check must not fire on an ordinary ledger; a false positive here downgrades
        // every install to `.unattested` and takes `isFullyAttested` with it.
        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
    }

    /// A reset restarts the sequence at 1, so the completeness check has to be satisfied again
    /// afterwards rather than remembering the pre-reset high-water mark.
    @Test("a reset ledger reports no sequence gap once it is written to again")
    func resetLedgerReportsNoSequenceGap() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())

        for index in 0..<3 {
            _ = try await store.append(draft(kind: "before-\(index)", payload: [:], accountAddress: Self.accountA))
        }
        try await store.resetAll()
        _ = try await store.append(draft(kind: "after", payload: [:], accountAddress: Self.accountA))

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
    }

    /// The completeness check has to travel with the archive, not just guard the live store.
    ///
    /// `.unattested` satisfies `isValid`, so an incomplete ledger exports happily. While the
    /// verifier only checked per-account continuity, that archive then verified as `.verified` with
    /// `isFullyAttested == true` — the local check defeated at the one boundary it exists for, by
    /// the entirely ordinary act of exporting first.
    @Test("an exported archive missing an account verifies as unattested, not verified")
    func exportedArchiveMissingAnAccountIsUnattested() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)
        let anchor = try await store.provenanceTrustAnchor()

        for index in 0..<2 {
            _ = try await store.append(draft(kind: "a-\(index)", payload: [:], accountAddress: Self.accountA))
            _ = try await store.append(draft(kind: "b-\(index)", payload: [:], accountAddress: Self.accountB))
        }
        _ = try await store.append(draft(kind: "a-last", payload: [:], accountAddress: Self.accountA))

        let victimRows = try context.fetch(FetchDescriptor<StoredReceipt>())
            .filter { $0.accountKey == Self.accountB.lowercased() }
        for row in victimRows {
            context.delete(row)
        }
        try context.save()
        await headStore.clearHead(for: Self.accountB.lowercased())

        // Exported, because `.unattested` is exportable by design — that is the whole point of the
        // scenario, not an incidental detail.
        let exported = try await store.exportAll()
        let verified = try ReceiptProvenanceVerifier.verify(
            exported,
            trustedSignerFingerprint: anchor.fingerprint
        )
        #expect(verified.isFullyAttested == false, "an incomplete archive must not claim full attestation")
        #expect(verified.status == .unattested, "\(verified.failureReason ?? "-")")
        #expect(verified.failureReason?.contains("missing 2 of 5") == true, "\(verified.failureReason ?? "-")")
    }

    @Test("a complete exported archive verifies as fully attested")
    func completeExportedArchiveIsFullyAttested() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())
        let anchor = try await store.provenanceTrustAnchor()

        for index in 0..<3 {
            _ = try await store.append(draft(kind: "a-\(index)", payload: [:], accountAddress: Self.accountA))
            _ = try await store.append(draft(kind: "b-\(index)", payload: [:], accountAddress: Self.accountB))
        }

        // The completeness check must not fire on an ordinary multi-account archive; a false positive
        // here silently downgrades every honest export.
        let verified = try ReceiptProvenanceVerifier.verify(
            try await store.exportAll(),
            trustedSignerFingerprint: anchor.fingerprint
        )
        #expect(verified.status == .verified, "\(verified.failureReason ?? "-")")
    }

    // MARK: - A device that cannot produce its signing identity

    /// A locked Keychain must not turn the ordinary crash window into a tampering verdict.
    ///
    /// `verifyIntegrity()` reads the current identity with `try?`, so a signer that cannot answer
    /// leaves `currentIdentitySeen` empty — and the one-row anchor tolerance was gated on that set.
    /// A ledger sitting in the window the tolerance exists for therefore fell through to
    /// `.tampered("Receipt chain head mismatch")`, the worst verdict available, because the device
    /// could not confirm something it was never asked to prove.
    @Test("a crash-window anchor is unattested, not tampering, when the signer cannot answer")
    func crashWindowWithUnavailableSignerIsUnattested() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = RevocableSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        _ = try await store.append(draft(kind: "first", payload: [:], accountAddress: Self.accountA))
        let second = try await store.append(draft(kind: "second", payload: [:], accountAddress: Self.accountA))
        // The anchor exactly one row behind the tip: what a crash between the row save and the anchor
        // write leaves behind.
        await headStore.saveHead(second.previousReceiptHash, for: Self.accountA.lowercased())

        // Now the Keychain locks, so the signer can neither sign nor name itself.
        await signer.revoke()

        let result = try await store.verifyIntegrity()
        // `.unattested` *is* the assertion: before this, the missing identity made the one-row
        // tolerance unreachable and this exact state reported `.tampered`. The summarized reason
        // names the unattributable signatures rather than the anchor, because a signer that cannot
        // state its key makes every row unattributable first — so the verdict, not the string, is
        // what pins the behaviour.
        #expect(result.status == .unattested, "\(result.failureReason ?? "-")")
        #expect(result.isValid, "a device that cannot answer has not found tampering")
        #expect(result.failureReason?.contains("head mismatch") == false, "\(result.failureReason ?? "-")")

        // And the anchor was left alone rather than healed on evidence the device does not have.
        #expect(await headStore.loadHead(for: Self.accountA.lowercased()) == second.previousReceiptHash)
    }

    /// The same tolerance must stay strict when the device *can* answer: an anchor further back than
    /// one row is still tampering, and an unavailable signer is not a way to launder that.
    @Test("an anchor further back than one receipt is still tampering with an unavailable signer")
    func deepAnchorRewindIsStillTampering() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = RevocableSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        let first = try await store.append(draft(kind: "first", payload: [:], accountAddress: Self.accountA))
        _ = try await store.append(draft(kind: "second", payload: [:], accountAddress: Self.accountA))
        _ = try await store.append(draft(kind: "third", payload: [:], accountAddress: Self.accountA))
        await headStore.saveHead(first.chainHash, for: Self.accountA.lowercased())
        await signer.revoke()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(result.failureReason?.contains("head mismatch") == true, "\(result.failureReason ?? "-")")
    }

    // MARK: - Verification racing the writes it verifies

    /// `verifyIntegrity()` is a read-modify-write of the same invariant `append` maintains, so it has
    /// to be queued with the appends rather than run alongside them.
    ///
    /// Unqueued it produced three distinct failures. The visible one: rows are fetched, then two
    /// suspensions follow (`publicKeyRepresentation()`, `loadAllHeads()`), so an append committing in
    /// between left the snapshot's tip one row behind the anchor — indistinguishable from a deleted
    /// tail, reported `.tampered`, and `exportAll()` refusing, on a ledger nobody had touched.
    ///
    /// The durable one is asserted below: the crash-window heal wrote back a head derived from the
    /// stale snapshot, *rewinding* an anchor that later appends had already advanced. After that the
    /// tip's `previousReceiptHash` matched no anchor at all and the account read `.tampered` until it
    /// received another receipt.
    @Test("verification running against concurrent appends never reports tampering")
    func verificationConcurrentWithAppendsNeverReportsTampering() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore, signer: SlowSigner())

        _ = try await store.append(draft(kind: "seed", payload: [:], accountAddress: Self.accountA))

        var verdicts: [ReceiptIntegrityVerificationResult] = []
        await withTaskGroup(of: ReceiptIntegrityVerificationResult?.self) { group in
            for index in 0..<6 {
                let appendDraft = draft(
                    kind: "concurrent-\(index)",
                    payload: [:],
                    accountAddress: Self.accountA
                )
                group.addTask {
                    _ = try? await store.append(appendDraft)
                    return nil
                }
                group.addTask {
                    try? await store.verifyIntegrity()
                }
            }
            for await verdict in group {
                if let verdict {
                    verdicts.append(verdict)
                }
            }
        }

        #expect(verdicts.isEmpty == false)
        for verdict in verdicts {
            #expect(verdict.status != .tampered, "a verify racing an append reported tampering: \(verdict.failureReason ?? "-")")
        }

        // The durable half: the anchor must name the current tip, not an ancestor a stale heal rewound
        // it to. A rewound anchor is what made this permanent rather than transient.
        let rows = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.accountSequenceID)])
        )
        let tip = try #require(rows.last)
        #expect(await headStore.loadHead(for: tip.accountKey) == tip.chainHash)

        // And the ledger has to still be exportable afterwards, which is the user-visible consequence.
        let settled = try await store.verifyIntegrity()
        #expect(settled.status == .verified, "\(settled.failureReason ?? "-")")
    }

    /// The reset leg of the ledger lock, which had no concurrent coverage at all.
    ///
    /// `resetAll()` deletes the rows and then clears the anchors, and an append landing between those
    /// two steps leaves a receipt whose anchor is then wiped — reported forever after as "persisted
    /// receipts without protected heads", recoverable only by destroying the history.
    @Test("a reset racing concurrent appends leaves a consistent ledger")
    func resetConcurrentWithAppendsLeavesConsistentLedger() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore, signer: SlowSigner())

        for index in 0..<3 {
            _ = try await store.append(draft(kind: "before-\(index)", payload: [:], accountAddress: Self.accountA))
        }

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<4 {
                let appendDraft = draft(
                    kind: "racing-\(index)",
                    payload: [:],
                    accountAddress: Self.accountA
                )
                group.addTask {
                    _ = try? await store.append(appendDraft)
                }
            }
            group.addTask {
                try? await store.resetAll()
            }
        }

        // Whatever order the queue settled into, the two halves have to agree: every surviving row is
        // chain-consistent, and every surviving anchor belongs to a row that is still there.
        //
        // `.verified` rather than `isValid`: the reset restarts `sequenceID` at 1 and re-anchors, and
        // this store holds one live signer throughout, so full attestation holds in every ordering.
        // `isValid` also accepts `.unattested`, which would hide a lost anchor or a signature that
        // stopped matching the current identity — the two things this race could actually damage.
        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")

        let rows = try context.fetch(FetchDescriptor<StoredReceipt>())
        let anchors = await headStore.loadAllHeads()
        let rowKeys = Set(rows.map(\.accountKey))
        #expect(Set(anchors.keys).subtracting(rowKeys).isEmpty, "an anchor outlived every row it described")

        // Still writable, and the chain picks up from whatever survived rather than forking.
        _ = try await store.append(draft(kind: "after", payload: [:], accountAddress: Self.accountA))
        let afterResult = try await store.verifyIntegrity()
        #expect(afterResult.isValid, "\(afterResult.failureReason ?? "-")")
    }

    // MARK: - Forward compatibility

    /// A receipt written by a newer build, carrying a `mode` this build has no case for, must not read
    /// as tampering.
    ///
    /// `StoredReceipt` degrades an unrecognized raw value to `.observe`/`.system` on read, so hashing
    /// the *typed* value re-hashed the stand-in instead of the bytes on disk and the row verified as
    /// "invalid chain hash" — a downgrade reported as an altered ledger. The envelope hashes the raw
    /// strings for exactly this reason, and nothing asserted it.
    @Test("a mode this build has no case for is a downgrade, not tampering")
    func unrecognizedModeIsNotTampering() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        _ = try await store.append(draft(kind: "from-the-future", payload: [:], accountAddress: Self.accountA))
        let stored = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)

        // Exactly what a newer build would have written: raw values with no case here, and integrity
        // metadata derived from those raw values.
        stored.modeRawValue = "supervise"
        stored.actorRawValue = "delegate"
        stored.chainHash = try ReceiptIntegrity.chainHash(for: stored)
        stored.signature = try await signer.sign(stored.chainHash).signature.base64EncodedString()
        try context.save()
        await headStore.saveHead(stored.chainHash, for: stored.accountKey)

        // Degraded on read — that part is expected and is why hashing the typed value was wrong.
        //
        // An unknown mode degrades to `.operate`, the *most* consequential case, not `.observe`. The
        // old `.observe` fallback was the one guess that could mislead a person: it is the least
        // alarming mode, so an Operate-class action written by a newer build would render on the audit
        // surface as passive observation. See ``StoredReceipt/mode``.
        #expect(stored.mode == .operate)
        #expect(stored.actor == .system)

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
    }

    // MARK: - Plain reads

    @Test("correlation and full-history reads return what was written, in timeline order")
    func correlationAndFullHistoryReads() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())

        _ = try await store.append(
            draft(kind: "first", payload: [:], accountAddress: Self.accountA, correlationID: "flow-1")
        )
        _ = try await store.append(
            draft(kind: "second", payload: [:], accountAddress: Self.accountA, correlationID: "flow-2")
        )
        _ = try await store.append(
            draft(kind: "third", payload: [:], accountAddress: Self.accountA, correlationID: "flow-1")
        )

        let correlated = try await store.receipts(forCorrelationID: "flow-1", limit: 10)
        #expect(correlated.map(\.trigger) == ["third", "first"])

        let all = try await store.allRecords()
        #expect(all.count == 3)
        // Newest first, the same order the console renders.
        #expect(all.map(\.sequenceID) == [3, 2, 1])
    }

    /// The `limit <= 0` guards. Without them these become unbounded fetches — a `fetchLimit` of 0
    /// means *no limit* in SwiftData, so `latest(limit: 0)` would have returned the whole ledger.
    @Test("a non-positive limit returns nothing rather than everything")
    func nonPositiveLimitsReturnNothing() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())

        _ = try await store.append(draft(kind: "only", payload: [:], accountAddress: Self.accountA, correlationID: "flow"))

        #expect(try await store.latest(limit: 0).isEmpty)
        #expect(try await store.latest(limit: -1).isEmpty)
        #expect(try await store.receipts(forCorrelationID: "flow", limit: 0).isEmpty)
        #expect(try await store.receipts(forCorrelationID: "flow", limit: -1).isEmpty)
        // The guard is a guard, not a disabled read.
        #expect(try await store.latest(limit: 1).count == 1)
    }

    // MARK: - Export refuses what it cannot describe

    /// An unreadable payload has to stop the export rather than travel inside it.
    ///
    /// `asReceiptRecord()` substitutes an empty payload when the `.externalStorage` blob is gone,
    /// which is right for the console and wrong for an archive: the record would carry the
    /// `payloadHash` of the real payload alongside an empty one, so every external verifier would
    /// recompute a mismatch and call a correctly written export tampered.
    @Test("an export is refused rather than signed around a payload it cannot read")
    func exportRefusesAnUnreadablePayload() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())

        _ = try await store.append(draft(kind: "corrupt", payload: [:], accountAddress: Self.accountA))
        let stored = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        stored.replaceDetailsDataForTesting(Data("not-json".utf8))
        try context.save()

        // Typed as an integrity failure, not a raw `DecodingError`: a caller matching on the export
        // error saw nothing at all, and the person saw an opaque failure instead of a verdict.
        await #expect(throws: ReceiptProvenanceExportError.self) {
            _ = try await store.exportAll()
        }
    }

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        try ReceiptStorageTestModelContainers.context()
    }

    /// The actor rather than the ``SwiftDataReceiptStore`` facade, because the facade does not expose
    /// `restoreHeads` and several cases here need it. Same ledger lock either way — the facade only
    /// forwards to this actor.
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

    private func draft(
        kind: String,
        payload: [String: ReceiptJSONValue],
        accountAddress: String? = nil,
        chainRawValue: String? = nil,
        correlationID: String? = nil
    ) -> ReceiptDraft {
        ReceiptDraft(
            createdAt: Date(timeIntervalSince1970: 100),
            actorDetail: .system,
            authorityDetail: nil,
            trigger: kind,
            scope: "accounts",
            summary: "Fixture",
            provenance: "test",
            isSuccess: true,
            correlationID: correlationID,
            timelineAccountAddress: accountAddress,
            timelineChainRawValue: chainRawValue,
            details: ReceiptPayload(values: payload)
        )
    }
}
