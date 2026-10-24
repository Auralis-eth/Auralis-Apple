import AuralisPrimaryModels
import PolicyCore
import RuntimeCore
@testable import RuntimeKit
import Testing

/// Pins the one property the two chain checks have to share: they must admit the *same* chain set.
///
/// They previously did not. `PolicyChainAllowlistCheck` hardcoded every non-Solana ``Chain`` (~30)
/// while `ChainScopeCheck` shipped a three-chain allowlist, so a single capability had two scopes
/// depending on entry point — `operator.onchain.prepareAction` refused Arbitrum while
/// `policy.draftTransaction` allowed it, and the wide allowlist was the one on the signing path.
/// Both now read ``StandardCheckConfiguration/allowedChains``, and nothing but this suite would
/// notice if one of them grew a private allowlist again.
@Suite("Chain scope agreement")
struct ChainScopeAgreementTests {
    private static let address = "0x0000000000000000000000000000000000000001"

    private func parameterProposal(chain: String) -> ActionProposal {
        ActionProposal(
            actor: .system,
            intent: "x",
            capability: .audioPlayback,
            impact: .readOnly,
            parameters: ["chain": chain]
        )
    }

    private func payloadProposal(chainID: String) -> ActionProposal {
        let payload = PolicyActionPayload.draftTransaction(
            from: Self.address,
            to: Self.address,
            value: "0x0",
            data: "0x",
            chainID: chainID
        )
        return ActionProposal(
            actor: .system,
            intent: "x",
            capability: payload.action.capabilityID,
            impact: CapabilityImpactMapping.defaultImpact(for: payload.action.capabilityID),
            parameters: payload.parameters
        )
    }

    /// Every chain the app knows about has to reach the same verdict on both sides.
    ///
    /// Each side is named in the reference forms it legitimately accepts: `chain.inScope` reads a
    /// proposal parameter, which may be a friendly alias, while the payload's `chainID` is an
    /// EIP-155 chain ID and so is only ever numeric, hex, or CAIP-2. The invariant under test is
    /// agreement about *scope*, not about reference syntax — see
    /// ``payloadCheckRefusesFriendlyAliases`` for the deliberate syntax difference.
    @Test("no chain can pass one chain check and fail the other")
    func bothChainChecksAdmitTheSameSet() async {
        let configuration = StandardCheckConfiguration.default
        let parameterCheck = ChainScopeCheck(allowed: configuration.allowedChains)
        let payloadCheck = PolicyChainAllowlistCheck(allowed: configuration.allowedChains)

        for chain in Chain.allCases where chain != .solanaMainnet && chain != .solanaDevnetTestnet {
            let parameterForms = [chain.rawValue, String(chain.chainId), "eip155:\(chain.chainId)"]
            let payloadForms = [String(chain.chainId), "eip155:\(chain.chainId)"]

            for reference in parameterForms {
                let viaParameter = await parameterCheck.evaluate(parameterProposal(chain: reference)).passed

                for payloadReference in payloadForms {
                    let viaPayload = await payloadCheck
                        .evaluate(payloadProposal(chainID: payloadReference)).passed

                    #expect(
                        viaParameter == viaPayload,
                        """
                        \(chain.rawValue): chain.inScope(\(reference))=\(viaParameter) \
                        policy.chain.allowed(\(payloadReference))=\(viaPayload)
                        """
                    )
                }
            }
        }
    }

    /// The payload check reads an EIP-155 chain ID, so a friendly alias there is a malformed value
    /// rather than a chain out of scope — and it fails closed. This is the one intentional
    /// difference between the two checks, pinned so it stays intentional.
    @Test("the payload check refuses a friendly alias even for an in-scope chain")
    func payloadCheckRefusesFriendlyAliases() async {
        let configuration = StandardCheckConfiguration.default
        let payloadCheck = PolicyChainAllowlistCheck(allowed: configuration.allowedChains)

        let result = await payloadCheck.evaluate(payloadProposal(chainID: "eth-mainnet"))

        #expect(result.passed == false)
        #expect(result.detail == "invalid chain ID")
        // Same chain, numeric form, same scope: allowed.
        #expect(await payloadCheck.evaluate(payloadProposal(chainID: "1")).passed)
    }

    @Test("widening the host's scope widens both checks together")
    func wideningTheScopeWidensBothChecks() async {
        let widened = StandardCheckConfiguration(allowedChains: [.ethMainnet, .arbMainnet])
        let parameterCheck = ChainScopeCheck(allowed: widened.allowedChains)
        let payloadCheck = PolicyChainAllowlistCheck(allowed: widened.allowedChains)

        #expect(await parameterCheck.evaluate(parameterProposal(chain: "arb-mainnet")).passed)
        #expect(await payloadCheck.evaluate(payloadProposal(chainID: String(Chain.arbMainnet.chainId))).passed)

        // And narrowing still bites on both: Polygon is outside the widened set.
        #expect(await parameterCheck.evaluate(parameterProposal(chain: "polygon-mainnet")).passed == false)
        #expect(
            await payloadCheck.evaluate(payloadProposal(chainID: String(Chain.polygonMainnet.chainId))).passed == false
        )
    }

    /// The scope the app ships (`RuntimeAssembly.governedChainScope`) has to cover every chain the
    /// wallet can sign on, or governed action refuses traffic the signer would happily have handled.
    ///
    /// This is the regression guard for a real hole: the app was inheriting
    /// ``StandardCheckConfiguration/default``'s three-chain set while `InAppWalletSigner.resolveChain`
    /// accepted any `Chain`, so `policy.draftTransaction` on Polygon, Arbitrum, or Optimism was
    /// blocked by `policy.chain.allowed` with no way for a person to tell the refusal apart from a
    /// policy denial. Adding a `Chain` case now widens this set automatically; narrowing it has to be
    /// deliberate enough to edit this test.
    @Test("the shipped scope admits every EVM chain the signer can resolve")
    func shippedScopeCoversEveryEVMChain() async {
        let payloadCheck = PolicyChainAllowlistCheck(allowed: StandardCheckConfiguration.allEVMChains)

        for chain in Chain.allCases where chain != .solanaMainnet && chain != .solanaDevnetTestnet {
            #expect(
                await payloadCheck.evaluate(payloadProposal(chainID: String(chain.chainId))).passed,
                "\(chain.rawValue) is outside the shipped governed chain scope"
            )
        }
        // And the exclusion is only Solana — not an accidental filter that also drops EVM chains.
        #expect(StandardCheckConfiguration.allEVMChains.count == Chain.allCases.count - 2)
        #expect(StandardCheckConfiguration.allEVMChains.contains(.solanaMainnet) == false)
        #expect(StandardCheckConfiguration.allEVMChains.contains(.solanaDevnetTestnet) == false)
    }

    /// Solana carries a `chainId`, but it is not an EIP-155 chain ID. A host that puts Solana in
    /// scope for reads must not thereby admit it to the EVM signing path by numeric coincidence.
    @Test("Solana stays out of the payload check even when the host puts it in scope")
    func solanaIsExcludedFromTheSigningPathRegardless() async {
        let withSolana = StandardCheckConfiguration(allowedChains: [.ethMainnet, .solanaMainnet])
        let payloadCheck = PolicyChainAllowlistCheck(allowed: withSolana.allowedChains)

        let result = await payloadCheck.evaluate(payloadProposal(chainID: String(Chain.solanaMainnet.chainId)))

        #expect(result.passed == false)
    }
}
