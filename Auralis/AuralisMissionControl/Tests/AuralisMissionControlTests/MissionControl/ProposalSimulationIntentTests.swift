import AuralisFoundation
import Foundation
@testable import AuralisMissionControl
import AuralisPolicy
import AuralisRuntime
import Testing

/// The Proposal Diff Viewer can only dry-run a proposal it can extract a transaction from.
///
/// `EVMTransactionIntent.from` used to look only for bare keys (`to`, `value`, `data`, `chain`), but a
/// governed wallet action reaches it through `RuntimeHost.runPolicyAction`, which builds its proposal
/// from `PolicyActionPayload.parameters` — and that namespaces every field under `payload.` so it
/// cannot collide with a plugin's own parameters. Nothing matched, so the simulator reported
/// `.notApplicable` for exactly the transactions it exists to warn about: a cleared transfer or an
/// approval got no revert or asset-change preview at all.
///
/// These tests go through the real `PolicyActionPayload.parameters`, so a future rename on either side
/// breaks them rather than silently re-muting the simulator.
@Suite("Proposal simulation intent extraction")
struct ProposalSimulationIntentTests {
    private func proposal(_ payload: PolicyActionPayload) -> ActionProposal {
        ActionProposal(
            actor: ActorRef(kind: .human),
            intent: "test",
            capability: .runPlugin,
            impact: .highRisk,
            parameters: payload.parameters
        )
    }

    @Test("a draftTransaction payload yields a complete intent")
    func draftTransactionYieldsIntent() throws {
        let payload = PolicyActionPayload.draftTransaction(
            from: "0x1111111111111111111111111111111111111111",
            to: "0x2222222222222222222222222222222222222222",
            value: "0x16345785d8a0000",
            data: "0xabcdef",
            chainID: "eip155:1"
        )

        let intent = try #require(EVMTransactionIntent.from(proposal: proposal(payload)))

        #expect(intent.to == "0x2222222222222222222222222222222222222222")
        #expect(intent.from == "0x1111111111111111111111111111111111111111")
        #expect(intent.valueHex == "0x16345785d8a0000")
        #expect(intent.dataHex == "0xabcdef")
        #expect(intent.chainKey == "eip155:1")
    }

    /// An approval must stay un-simulatable here, because this layer cannot build its calldata.
    ///
    /// `approveSpending` carries `token`/`spender`/`amount` but no `data` — the
    /// `approve(address,uint256)` bytes are assembled later by the wallet executor. Accepting the token
    /// contract as a destination would therefore dry-run a 0-value, 0-calldata no-op and render it to
    /// the user as "succeeds, no asset changes" for an approval whose real calldata was never
    /// simulated. `.notApplicable` is the honest answer; a confident wrong one on the last check before
    /// signing is worse than none.
    @Test("an approveSpending payload yields no intent, because its calldata does not exist yet")
    func approveSpendingYieldsNoIntent() {
        let payload = PolicyActionPayload.approveSpending(
            token: "0x3333333333333333333333333333333333333333",
            spender: "0x4444444444444444444444444444444444444444",
            amount: "1000000",
            owner: "0x5555555555555555555555555555555555555555",
            chainID: "eip155:8453"
        )

        #expect(EVMTransactionIntent.from(proposal: proposal(payload)) == nil)
    }

    /// A zero-value, no-calldata `draftTransaction` extracts as exactly that, and the simulator is
    /// expected to dry-run it.
    ///
    /// This deliberately does *not* assert "an intent is never an all-zero no-op" — that invariant is
    /// false, and asserting it with a non-zero `value` would be tautological. A user can legitimately
    /// draft a 0-wei call (a contract ping, a nonce burn), and simulating it is correct and harmless.
    /// The approval case is different, and is covered by ``approveSpendingYieldsNoIntent``: there the
    /// all-zero shape is a *fabrication*, because the real calldata exists but has not been built yet.
    @Test("a zero-value, no-calldata draft extracts faithfully rather than being suppressed")
    func zeroValueDraftExtractsFaithfully() throws {
        let payload = PolicyActionPayload.draftTransaction(
            from: "0x1111111111111111111111111111111111111111",
            to: "0x2222222222222222222222222222222222222222",
            value: "0",
            data: "",
            chainID: "eip155:1"
        )

        let intent = try #require(EVMTransactionIntent.from(proposal: proposal(payload)))

        #expect(intent.to == "0x2222222222222222222222222222222222222222")
        #expect(intent.valueHex == "0x0")
        #expect(intent.dataHex == "0x")
    }

    /// The bare spellings still work — the `payload.*` keys were added alongside them, not instead of
    /// them, so a proposal built by any other producer keeps simulating.
    @Test("unprefixed parameter keys still extract")
    func unprefixedKeysStillExtract() throws {
        let proposal = ActionProposal(
            actor: ActorRef(kind: .human),
            intent: "test",
            capability: .runPlugin,
            impact: .highRisk,
            parameters: [
                "to": "0x6666666666666666666666666666666666666666",
                "value": "0x1",
                "data": "0x",
                "chain": "base"
            ]
        )

        let intent = try #require(EVMTransactionIntent.from(proposal: proposal))

        #expect(intent.to == "0x6666666666666666666666666666666666666666")
        #expect(intent.chainKey == "base")
    }

    /// A payload with no destination is still correctly `nil` — the fix widened key matching, it did
    /// not make the extractor fabricate an intent.
    @Test("a payload with no destination still yields no intent")
    func payloadWithoutDestinationYieldsNil() {
        let payload = PolicyActionPayload.signMessage(
            text: "hello",
            address: "0x7777777777777777777777777777777777777777",
            chainID: "eip155:1"
        )

        #expect(EVMTransactionIntent.from(proposal: proposal(payload)) == nil)
    }
}
