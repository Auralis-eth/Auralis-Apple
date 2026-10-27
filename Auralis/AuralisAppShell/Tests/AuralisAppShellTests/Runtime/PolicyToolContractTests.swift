import AuralisCrypto
import AuralisPolicy
import AuralisRuntime
@testable import AuralisAppShell
import Testing

struct PolicyToolContractTests {
    private let address = "0x0000000000000000000000000000000000000001"

    @Test
    func everyPolicyToolDeclaresACompleteGovernanceContract() {
        #expect(PolicyActionCatalog.tools.count == PolicyControlledAction.allCases.count)
        for tool in PolicyActionCatalog.tools {
            #expect(tool.inputSchema.fields.isEmpty == false, "\(tool.id) needs an input schema")
            #expect(tool.outputSchema.fields.isEmpty == false, "\(tool.id) needs an output schema")
            #expect(tool.requiredCheckIDs.isEmpty == false, "\(tool.id) needs deterministic checks")
            #expect(tool.requiresReceipt, "\(tool.id) must require a receipt")
            #expect(tool.definitionProblems.isEmpty, "\(tool.id) has an invalid definition")
        }
    }

    @Test
    func policySchemasAcceptMatchingPayloads() throws {
        let payloads: [PolicyActionPayload] = [
            .signMessage(text: "hello", address: address, chainID: "eip155:1"),
            .approveSpending(token: address, spender: address, amount: "100", owner: address, chainID: "0x1"),
            .draftTransaction(from: address, to: address, value: "0x0", data: "0x", chainID: "1"),
            .runPlugin(pluginID: "calendar", parameters: ["query": "today"])
        ]

        for payload in payloads {
            let tool = try #require(PolicyActionCatalog.tools.first {
                $0.id == PolicyActionCatalog.toolID(for: payload.action)
            })
            #expect(tool.inputSchema.validationProblems(against: payload.parameters).isEmpty)
        }
    }

    @Test
    func policySchemasAcceptTheRuntimesRecordShapeStamp() throws {
        // The host stamps record-shape versions onto every proposal it builds, and these tools have
        // strict schemas. If they didn't declare the stamped fields, every real policy action would
        // come back as `.revise("unexpected field …")` instead of running.
        let payloads: [PolicyActionPayload] = [
            .signMessage(text: "hello", address: address, chainID: "eip155:1"),
            .approveSpending(token: address, spender: address, amount: "100", owner: address, chainID: "0x1"),
            .draftTransaction(from: address, to: address, value: "0x0", data: "0x", chainID: "1"),
            .runPlugin(pluginID: "calendar", parameters: ["query": "today"])
        ]

        for payload in payloads {
            let tool = try #require(PolicyActionCatalog.tools.first {
                $0.id == PolicyActionCatalog.toolID(for: payload.action)
            })
            let stamped = payload.parameters.merging(RecordSchemaKey.currentDeclaration) { existing, _ in existing }

            #expect(
                tool.inputSchema.validationProblems(against: stamped).isEmpty,
                "\(tool.id) rejects the runtime's record-shape stamp"
            )
        }
    }

    @Test
    func payloadKindCannotClaimAnotherPolicyTool() throws {
        let tool = try #require(PolicyActionCatalog.tools.first {
            $0.id == PolicyActionCatalog.toolID(for: .signMessage)
        })
        let parameters = PolicyActionPayload.approveSpending(
            token: address,
            spender: address,
            amount: "1",
            owner: address,
            chainID: "1"
        ).parameters

        #expect(tool.inputSchema.validationProblems(against: parameters).isEmpty == false)
    }

    @Test(arguments: ["1", "0x1", "eip155:1"])
    func supportedChainRepresentationsPass(chainID: String) async {
        let payload = PolicyActionPayload.signMessage(text: "hello", address: address, chainID: chainID)
        let proposal = proposal(for: payload)

        #expect(await PolicyChainAllowlistCheck(allowed: StandardCheckConfiguration.default.allowedChains)
            .evaluate(proposal).passed)
    }

    @Test
    func unsupportedChainFailsClosed() async {
        let payload = PolicyActionPayload.signMessage(text: "hello", address: address, chainID: "999999998")
        let result = await PolicyChainAllowlistCheck(allowed: StandardCheckConfiguration.default.allowedChains)
            .evaluate(proposal(for: payload))

        #expect(result.passed == false)
    }

    /// The unlimited amounts must be refused however they are *spelled*, not only in the two
    /// canonical forms. `.unsignedQuantity` accepts hexadecimal of any length and decimal with
    /// leading zeros, so an exact string match let every padded variant of 2²⁵⁶−1 through as
    /// "bounded" — an infinite approval cleared by the check that exists to refuse it.
    @Test(arguments: [
        // Zero, in each base and with padding.
        "0",
        "0x0",
        "00",
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        // 2²⁵⁶−1, canonical.
        "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "115792089237316195423570985008687907853269984665640564039457584007913129639935",
        // 2²⁵⁶−1, same value with leading zeros.
        "0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "0115792089237316195423570985008687907853269984665640564039457584007913129639935",
        // 2²⁵⁶−1 in upper case, which normalisation has to fold before comparing.
        "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
        // Above 2²⁵⁶−1: not representable on-chain, so malformed rather than merely large.
        "0x1ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "115792089237316195423570985008687907853269984665640564039457584007913129639936"
    ])
    func zeroAndUnlimitedApprovalsFail(amount: String) async {
        let payload = PolicyActionPayload.approveSpending(
            token: address,
            spender: address,
            amount: amount,
            owner: address,
            chainID: "1"
        )

        #expect(await BoundedApprovalCheck().evaluate(proposal(for: payload)).passed == false)
    }

    /// The other half of the contract: normalising for the padded cases above must not start
    /// refusing ordinary approvals, including one a single unit below the maximum.
    @Test(arguments: [
        "1",
        "0x1",
        "0x0001",
        "100",
        "0100",
        "1000000000000000000",
        "115792089237316195423570985008687907853269984665640564039457584007913129639934",
        "0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe"
    ])
    func boundedApprovalsPass(amount: String) async {
        let payload = PolicyActionPayload.approveSpending(
            token: address,
            spender: address,
            amount: amount,
            owner: address,
            chainID: "1"
        )

        #expect(await BoundedApprovalCheck().evaluate(proposal(for: payload)).passed)
    }

    private func proposal(for payload: PolicyActionPayload) -> ActionProposal {
        ActionProposal(
            actor: .human,
            intent: payload.action.title,
            capability: payload.action.capabilityID,
            impact: CapabilityImpactMapping.defaultImpact(for: payload.action.capabilityID),
            parameters: payload.parameters
        )
    }
}
