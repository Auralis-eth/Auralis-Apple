@testable import Auralis
import AuralisPrimaryModels
import Foundation
import AuralisReceipts
import Testing

/// How a receipt's stored account key is compared against the timeline's active scope.
///
/// The two sides are written by different code with different rules —
/// `AuralisReceipts.ReceiptAccountAddress.resolve` lowercases the stored key, while the scope side
/// went through `AuralisEthereumAddress`, which *adds* a `0x` prefix. Anything that makes those two
/// disagree removes a receipt from its own account's timeline silently, so the agreement is pinned
/// here rather than left to the two call sites staying in step.
@Suite("Receipt timeline account scope")
struct ReceiptTimelineAccountScopeTests {
    private let checksummed = "0xAbC0000000000000000000000000000000000001"
    private let lowercased = "0xabc0000000000000000000000000000000000001"
    private let unprefixed = "abc0000000000000000000000000000000000001"

    private func record(accountAddress: String?) -> ReceiptTimelineRecord {
        ReceiptTimelineRecord(
            id: UUID(),
            sequenceID: 1,
            createdAt: Date(timeIntervalSince1970: 1_000),
            actor: .user,
            mode: .observe,
            trigger: "accounts.selected",
            scope: "accounts",
            summary: "Selected account",
            provenance: "user_provided",
            isSuccess: true,
            correlationID: "c-1",
            details: ReceiptPayload(values: [:]),
            accountAddress: accountAddress
        )
    }

    private func scope(_ address: String) -> ReceiptTimelineScope {
        ReceiptTimelineScope(accountAddress: address, chain: .ethMainnet)
    }

    /// The pre-fix defect. `ReceiptAccountAddress.resolve` stores `trimmed.lowercased()`, so a
    /// caller that passed an unprefixed address stored one — and the scope side normalized to
    /// `0x…`, which could never equal it. The receipt vanished from its own account's timeline.
    @Test("an unprefixed stored key still matches the same address in the scope")
    func unprefixedStoredKeyMatches() {
        #expect(record(accountAddress: unprefixed).matches(scope(checksummed)))
        #expect(record(accountAddress: unprefixed).matches(scope(lowercased)))
        #expect(record(accountAddress: unprefixed).matches(scope(unprefixed)))
    }

    @Test("case differences on either side do not hide a receipt")
    func caseDifferencesMatch() {
        #expect(record(accountAddress: lowercased).matches(scope(checksummed)))
        #expect(record(accountAddress: checksummed).matches(scope(lowercased)))
    }

    /// The filter still has to filter — normalizing both sides must not collapse distinct accounts.
    @Test("a different account is still excluded")
    func differentAccountIsExcluded() {
        let other = "0xdef0000000000000000000000000000000000002"
        #expect(record(accountAddress: lowercased).matches(scope(other)) == false)
    }

    /// `resolve` deliberately accepts keys that are not addresses rather than dropping those
    /// receipts onto the global timeline, so the comparison has to handle them on both sides too.
    @Test("non-address account keys compare case-insensitively rather than falling through")
    func nonAddressKeysCompare() {
        #expect(record(accountAddress: "Vitalik.eth").matches(scope("vitalik.eth")))
        #expect(record(accountAddress: "vitalik.eth").matches(scope("someone.eth")) == false)
    }

    /// Unchanged behaviour, asserted so the normalization change cannot quietly alter it: an empty
    /// scope means "no active account", which does not filter by account at all.
    @Test("an empty scope address does not filter by account")
    func emptyScopeDoesNotFilter() {
        #expect(record(accountAddress: lowercased).matches(scope("")))
    }

    /// A receipt with no account key is global and belongs in every account's timeline.
    @Test("a receipt with no account key matches any scope")
    func receiptWithoutAccountMatchesAnyScope() {
        #expect(record(accountAddress: nil).matches(scope(checksummed)))
    }

    // MARK: - The fetch predicates must normalize the same way

    /// The in-memory comparison and the SwiftData predicates have to agree, because a predicate runs
    /// *first* and a post-fetch filter can only narrow. Normalizing only `matches(_:)` left the
    /// documented defect live on both the detail and timeline screens.
    @Test("the shared account key normalizes prefixed, unprefixed, and checksummed forms identically")
    func accountKeyAgreesAcrossSpellings() {
        let expected = ReceiptTimelineRecord.accountKey(lowercased)

        #expect(expected != nil)
        #expect(ReceiptTimelineRecord.accountKey(checksummed) == expected)
        #expect(ReceiptTimelineRecord.accountKey(unprefixed) == expected)
    }

    @Test("the shared account key passes non-address keys through lowercased")
    func accountKeyLowercasesNonAddresses() {
        #expect(ReceiptTimelineRecord.accountKey("Vitalik.eth") == "vitalik.eth")
        #expect(ReceiptTimelineRecord.accountKey("") == nil)
        #expect(ReceiptTimelineRecord.accountKey("   ") == nil)
        #expect(ReceiptTimelineRecord.accountKey(nil) == nil)
    }

    // MARK: - Chain filtering is a list concern, not a visibility boundary

    private func record(accountAddress: String?, chainRawValue: String?) -> ReceiptTimelineRecord {
        ReceiptTimelineRecord(
            id: UUID(),
            sequenceID: 1,
            createdAt: Date(timeIntervalSince1970: 1_000),
            actor: .user,
            mode: .observe,
            trigger: "accounts.selected",
            scope: "accounts",
            summary: "Selected account",
            provenance: "user_provided",
            isSuccess: true,
            correlationID: "c-1",
            details: ReceiptPayload(values: [:]),
            accountAddress: accountAddress,
            chainRawValue: chainRawValue
        )
    }

    /// A receipt recorded on another chain is still the user's receipt. The detail route addresses it
    /// by id, so filtering it out there produced a dead end claiming the row "could not be found in
    /// local storage" — a false statement about a row that exists.
    @Test("a foreign-chain receipt stays account-visible even though the chain filter excludes it")
    func chainFilterDoesNotHideReceiptFromItsOwner() {
        let foreignChain = record(accountAddress: lowercased, chainRawValue: Chain.baseMainnet.rawValue)
        let ethereumScope = scope(checksummed)

        #expect(foreignChain.matchesAccountScope(ethereumScope))
        #expect(foreignChain.matchesChainFilter(ethereumScope) == false)
        #expect(foreignChain.matches(ethereumScope) == false)
    }

    /// The account boundary is never relaxed by the split: another account's receipt stays hidden
    /// regardless of chain.
    @Test("another account's receipt fails the account scope on every chain")
    func accountBoundaryHoldsAcrossChains() {
        let other = record(
            accountAddress: "0xdef0000000000000000000000000000000000002",
            chainRawValue: Chain.ethMainnet.rawValue
        )

        #expect(other.matchesAccountScope(scope(checksummed)) == false)
        #expect(other.matches(scope(checksummed)) == false)
    }
}
