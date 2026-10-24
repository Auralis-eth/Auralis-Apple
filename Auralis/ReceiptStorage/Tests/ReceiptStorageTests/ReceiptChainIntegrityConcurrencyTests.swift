import AuralisPrimaryModels
import Foundation
import ReceiptsCore
import ReceiptStorage
import RuntimeCore
import SwiftData
import Testing

/// The receipt ledger is a signed hash chain, so every append depends on the one before it. Two
/// things used to break that, both silently and both permanently — the rows are signed and
/// immutable, so once `verifyIntegrity()` says invalid it says so forever and `exportAll()` refuses
/// to run for the life of the installation.
///
/// 1. `append` derived its sequence and previous hash, then awaited `signer.sign(_:)` before
///    inserting. An actor is only serialized *between* suspension points, so a second append
///    entering during that signature chained off the same previous hash (F-1's failure class).
/// 2. The chain hash committed to a normalized account address while the stored row kept the raw
///    one, so a checksummed address hashed as one string and verified as another.
@MainActor
struct ReceiptChainIntegrityConcurrencyTests {
    /// Longer than the shared default: these cases open six to eight concurrent appends and want
    /// every one of them inside the window at once.
    private static let slowSigner = SlowSigner(delay: .milliseconds(20))

    private static let account = "0x1111111111111111111111111111111111111111"

    private func store(signer: any ReceiptSigning) throws -> ReceiptPersistenceStore {
        ReceiptPersistenceStore(
            modelContainer: try ReceiptStorageTestModelContainers.context().container,
            integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
            signer: signer
        )
    }

    private func draft(_ kind: String, account: String?) -> ReceiptDraft {
        ReceiptDraft(
            createdAt: Date(timeIntervalSince1970: 100),
            category: "accounts",
            kind: kind,
            correlationID: nil,
            payload: ReceiptPayload(values: [:]),
            actorDetail: .system,
            authorityDetail: nil,
            timelineAccountAddress: account
        )
    }

    // MARK: - Concurrent appends

    @Test("concurrent appends keep one unbroken account chain")
    func concurrentAppendsKeepChainIntact() async throws {
        let store = try store(signer: Self.slowSigner)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<6 {
                group.addTask {
                    _ = try? await store.append(self.draft("concurrent-\(index)", account: Self.account))
                }
            }
        }

        // `.verified`, not `isValid`. `isValid` is only `status != .tampered`, so it also accepts
        // `.unattested` — and these stores hold a live signer for their whole lifetime, so anything
        // short of full attestation (a signature that stopped matching the current identity, or the
        // Keychain anchor check going quiet) is a regression this test exists to catch.
        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "chain corrupted by concurrent appends: \(result.failureReason ?? "-")")

        // The sequence is the thing that broke: duplicates, not gaps. Asserted directly so a future
        // change that makes `verifyIntegrity` more permissive cannot hide the same defect.
        let records = try await store.latest(limit: 10)
        let accountSequenceIDs = records.map(\.accountSequenceID).sorted()
        #expect(accountSequenceIDs == [1, 2, 3, 4, 5, 6], "account sequence was not allocated exactly once per append")
        #expect(Set(records.map(\.chainHash)).count == 6, "two receipts share a chain hash")
    }

    @Test("a concurrently appended ledger still exports")
    func concurrentAppendsStillExport() async throws {
        let store = try store(signer: Self.slowSigner)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<4 {
                group.addTask {
                    _ = try? await store.append(self.draft("exported-\(index)", account: Self.account))
                }
            }
        }

        // `exportAll()` throws `integrityFailure` on a broken chain, so this is the user-visible
        // consequence: provenance export is refused on data that was written correctly.
        let exported = try await store.exportAll()
        let decoded = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: exported)
        #expect(decoded.records.count == 4)
    }

    @Test("appends interleaved across two accounts keep both chains intact")
    func concurrentAppendsAcrossAccountsKeepBothChains() async throws {
        let store = try store(signer: Self.slowSigner)
        let other = "0x2222222222222222222222222222222222222222"

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<4 {
                group.addTask {
                    _ = try? await store.append(self.draft("a-\(index)", account: Self.account))
                }
                group.addTask {
                    _ = try? await store.append(self.draft("b-\(index)", account: other))
                }
            }
        }

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "chain corrupted across accounts: \(result.failureReason ?? "-")")

        // Asserted because the appends above are `try?`: an empty ledger verifies as `.verified`, so
        // the check alone would pass if all eight appends had thrown. Each account must have its own
        // chain numbered from 1, which is also what a cross-account sequence collision would break.
        let records = try await store.latest(limit: 20)
        #expect(records.count == 8)
        let byAccount = Dictionary(grouping: records) { $0.accountAddress ?? "none" }
        #expect(byAccount.count == 2)
        for (account, accountRecords) in byAccount {
            #expect(
                accountRecords.map(\.accountSequenceID).sorted() == [1, 2, 3, 4],
                "account \(account) did not get exactly one chain of four"
            )
        }
    }

    // MARK: - Account-address resolution

    @Test("a checksummed account address still verifies")
    func checksummedAccountAddressVerifies() async throws {
        let store = try store(signer: SoftwareReceiptSigner())

        _ = try await store.append(
            draft("checksummed", account: "0xAbCdEf1111111111111111111111111111111111")
        )

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "a checksummed address broke the chain hash: \(result.failureReason ?? "-")")
    }

    @Test("a padded account address still verifies and lands on one chain")
    func paddedAccountAddressVerifies() async throws {
        let store = try store(signer: SoftwareReceiptSigner())

        _ = try await store.append(draft("padded", account: "  \(Self.account)  "))
        _ = try await store.append(draft("plain", account: Self.account))

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "a padded address broke the chain: \(result.failureReason ?? "-")")
        // Same account, so the second receipt must continue the first one's chain rather than start
        // a second one at sequence 1.
        let records = try await store.latest(limit: 2)
        #expect(records.map(\.accountSequenceID).sorted() == [1, 2])
    }

    /// The draft carries no explicit address but its payload does. The row took the payload's
    /// address while the hash committed to `nil`, so one receipt was enough to invalidate the ledger.
    @Test("an address carried only in the payload still verifies")
    func payloadOnlyAccountAddressVerifies() async throws {
        let store = try store(signer: SoftwareReceiptSigner())

        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "payload-address",
                correlationID: nil,
                payload: ReceiptPayload(values: ["accountAddress": .string(Self.account)]),
                actorDetail: .system,
                authorityDetail: nil
            )
        )

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "a payload-carried address broke the chain hash: \(result.failureReason ?? "-")")
    }
}
