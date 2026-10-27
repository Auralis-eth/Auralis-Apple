import AuralisPolicy
import AuralisRuntime
@testable import RuntimeKit
import Testing

@Suite("Policy payload address checksum check")
struct PolicyAddressChecksumCheckTests {
    // Canonical EIP-55 vectors from the spec, so a failure here is a checksum bug and not a
    // disagreement about what the correct casing is.
    private static let checksummed = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
    private static let otherChecksummed = "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359"
    private static let thirdChecksummed = "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB"
    /// The same address as ``checksummed`` with one letter's case flipped: still mixed case, so it
    /// still claims to carry a checksum, but the checksum is now wrong.
    private static let badChecksum = "0x5AAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
    private static let unchecksummed = "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"

    private func evaluate(_ payload: PolicyActionPayload) async -> DeterministicCheckResult {
        await PolicyAddressChecksumCheck().evaluate(
            ActionProposal(
                actor: .human,
                intent: "x",
                capability: payload.action.capabilityID,
                impact: .readOnly,
                parameters: payload.parameters
            )
        )
    }

    // MARK: - signMessage

    @Test("a correctly checksummed signing address passes without a note")
    func checksummedSigningAddressPasses() async {
        let result = await evaluate(.signMessage(text: "hi", address: Self.checksummed, chainID: "1"))

        #expect(result.passed)
        #expect(result.detail == nil)
    }

    @Test("a failed checksum on the signing address is refused and names the field")
    func badChecksumOnSigningAddressFails() async {
        let result = await evaluate(.signMessage(text: "hi", address: Self.badChecksum, chainID: "1"))

        #expect(result.passed == false)
        #expect(result.detail == "payload.address failed its EIP-55 checksum")
    }

    @Test("a malformed signing address is refused")
    func malformedSigningAddressFails() async {
        let result = await evaluate(.signMessage(text: "hi", address: "0x1234", chainID: "1"))

        #expect(result.passed == false)
        #expect(result.detail == "payload.address is not a well-formed address")
    }

    /// The deliberate soft spot: an all-lowercase address carries no checksum to verify, and dapps
    /// send them constantly, so it passes with a note rather than blocking a live session.
    @Test("an unchecksummed address passes but is recorded as unverified")
    func unchecksummedAddressPassesWithNote() async {
        let result = await evaluate(.signMessage(text: "hi", address: Self.unchecksummed, chainID: "1"))

        #expect(result.passed)
        // Asserted on `severity`, not just `passed`: this is the signing path, and a regression to a
        // plain `.pass` would keep `passed == true` and the same detail while silently dropping the
        // result out of `warnings` — so it would stop reaching the approval prompt and would render
        // in Mission Control as a clean green check.
        #expect(result.severity == .warning)
        #expect(result.detail == "well-formed but unchecksummed: payload.address")
    }

    // MARK: - approveSpending (every address field, not just the first)

    @Test("a failed checksum on the spender is refused", arguments: [
        ("payload.token", 0),
        ("payload.spender", 1),
        ("payload.owner", 2)
    ])
    func badChecksumOnAnyApprovalFieldFails(field: String, position: Int) async {
        var addresses = [Self.checksummed, Self.otherChecksummed, Self.thirdChecksummed]
        addresses[position] = Self.badChecksum

        let result = await evaluate(
            .approveSpending(
                token: addresses[0],
                spender: addresses[1],
                amount: "1000",
                owner: addresses[2],
                chainID: "1"
            )
        )

        #expect(result.passed == false)
        #expect(result.detail == "\(field) failed its EIP-55 checksum")
    }

    @Test("an approval with every address correctly checksummed passes")
    func fullyChecksummedApprovalPasses() async {
        let result = await evaluate(
            .approveSpending(
                token: Self.checksummed,
                spender: Self.otherChecksummed,
                amount: "1000",
                owner: Self.thirdChecksummed,
                chainID: "1"
            )
        )

        #expect(result.passed)
        #expect(result.detail == nil)
    }

    // MARK: - draftTransaction

    @Test("an absent recipient is a contract creation, not a missing address")
    func nilRecipientPasses() async {
        let result = await evaluate(
            .draftTransaction(from: Self.checksummed, to: nil, value: "0", data: "0x", chainID: "1")
        )

        #expect(result.passed)
        #expect(result.detail == nil)
    }

    @Test("a failed checksum on the recipient is refused")
    func badChecksumOnRecipientFails() async {
        let result = await evaluate(
            .draftTransaction(
                from: Self.checksummed,
                to: Self.badChecksum,
                value: "0",
                data: "0x",
                chainID: "1"
            )
        )

        #expect(result.passed == false)
        #expect(result.detail == "payload.to failed its EIP-55 checksum")
    }

    // MARK: - Posture

    @Test("a plugin run has no address to verify")
    func pluginRunHasNoAddress() async {
        let result = await evaluate(.runPlugin(pluginID: "p", parameters: [:]))

        #expect(result.passed)
        #expect(result.detail == "no address required")
    }

    @Test("an undecodable payload fails closed")
    func undecodablePayloadFailsClosed() async {
        let result = await PolicyAddressChecksumCheck().evaluate(
            ActionProposal(
                actor: .human,
                intent: "x",
                capability: .signMessage,
                impact: .readOnly,
                parameters: ["payload.kind": "signMessage"]
            )
        )

        #expect(result.passed == false)
        #expect(result.detail == "payload cannot be decoded")
    }

    /// The failure detail lands in the worklog permanently, so it names the offending field and
    /// never the address value itself.
    @Test("no failure detail echoes the address into the record")
    func detailNeverEchoesTheAddress() async {
        let results = [
            await evaluate(.signMessage(text: "hi", address: Self.badChecksum, chainID: "1")),
            await evaluate(.signMessage(text: "hi", address: "0x1234", chainID: "1")),
            await evaluate(.signMessage(text: "hi", address: Self.unchecksummed, chainID: "1"))
        ]

        for result in results {
            let detail = result.detail ?? ""
            #expect(detail.contains(Self.badChecksum) == false)
            #expect(detail.contains(Self.unchecksummed) == false)
            #expect(detail.contains("1234") == false)
        }
    }

    @Test("the check resolves through the registry under its published ID")
    func checkResolvesThroughRegistry() async {
        let registry = DeterministicCheckRegistry()
        await registry.registerPolicyToolChecks()

        let results = await registry.evaluate(
            ids: [PolicyToolCheckID.addressChecksum],
            for: ActionProposal(
                actor: .human,
                intent: "x",
                capability: .signMessage,
                impact: .readOnly,
                parameters: PolicyActionPayload
                    .signMessage(text: "hi", address: Self.badChecksum, chainID: "1")
                    .parameters
            )
        )

        // Not "unregistered check" — the real check ran and refused it.
        #expect(results.firstFailure?.detail == "payload.address failed its EIP-55 checksum")
    }
}
