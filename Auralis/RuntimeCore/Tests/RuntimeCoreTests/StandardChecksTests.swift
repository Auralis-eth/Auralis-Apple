import AuralisPrimaryModels
import Foundation
@testable import RuntimeCore
import Testing

@Suite("Standard deterministic checks")
struct StandardChecksTests {
    /// A real EIP-55 checksummed address (vitalik.eth), which is also the On-Chain Watch seed.
    private static let checksummedAddress = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"

    private func proposal(_ parameters: [String: String]) -> ActionProposal {
        ActionProposal(actor: .system, intent: "x", capability: .audioPlayback, impact: .readOnly, parameters: parameters)
    }

    @Test
    func addressFormat() async {
        let check = AddressFormatCheck()
        #expect(await check.evaluate(proposal(["address": "0x" + String(repeating: "a", count: 40)])).passed)
        #expect(await check.evaluate(proposal(["address": "0xnothex"])).passed == false)
        #expect(await check.evaluate(proposal([:])).passed) // absent → passes
    }

    @Test("a checksummed address passes and a case-flipped one is refused")
    func addressChecksumIsEnforced() async {
        let check = AddressFormatCheck()

        #expect(await check.evaluate(proposal(["address": Self.checksummedAddress])).passed)

        // The single error class a shape-only check cannot catch: still 40 valid hex characters,
        // still mixed case, but the EIP-55 checksum no longer matches.
        let flipped = "0xd8Da6BF26964aF9D7eEd9e03E53415D37aA96045"
        let result = await check.evaluate(proposal(["address": flipped]))
        #expect(result.passed == false)
        #expect(result.detail == "address failed its EIP-55 checksum")
    }

    @Test("a single-case address passes but says it carried no checksum")
    func unchecksummedAddressPassesExplicitly() async {
        let result = await AddressFormatCheck()
            .evaluate(proposal(["address": Self.checksummedAddress.lowercased()]))

        #expect(result.passed)
        #expect(result.detail == "address is well-formed but unchecksummed")
    }

    @Test("the failure detail never echoes the address into the permanent record")
    func addressFailureDetailIsValueFree() async {
        let flipped = "0xd8Da6BF26964aF9D7eEd9e03E53415D37aA96045"
        let detail = await AddressFormatCheck().evaluate(proposal(["address": flipped])).detail ?? ""

        #expect(!detail.contains("0x"))
    }

    @Test
    func ensFormat() async {
        let check = ENSNameFormatCheck()
        #expect(await check.evaluate(proposal(["ens": "vitalik.eth"])).passed)
        #expect(await check.evaluate(proposal(["ens": "nope.com"])).passed == false)
        #expect(await check.evaluate(proposal([:])).passed) // absent → passes
    }

    @Test("subdomains are valid ENS names")
    func ensSubdomainsAreAccepted() async {
        let check = ENSNameFormatCheck()

        #expect(await check.evaluate(proposal(["ens": "pay.vitalik.eth"])).passed)
        #expect(await check.evaluate(proposal(["ens": "a.b.c.vitalik.eth"])).passed)
        #expect(await check.evaluate(proposal(["ens": "PAY.Vitalik.ETH"])).passed) // case-insensitive
    }

    @Test("non-ASCII labels are refused rather than treated as valid")
    func ensRejectsNonASCIILabels() async {
        let check = ENSNameFormatCheck()

        // `vitalik` with a Cyrillic `а` — renders identically, resolves to a different name.
        let homoglyph = await check.evaluate(proposal(["ens": "vit\u{0430}lik.eth"]))
        #expect(homoglyph.passed == false)
        #expect(homoglyph.detail == "ENS labels accept only a-z, 0-9, and hyphens")

        #expect(await check.evaluate(proposal(["ens": "🎉.eth"])).passed == false)
    }

    @Test("malformed ENS shapes are refused")
    func ensRejectsMalformedShapes() async {
        let check = ENSNameFormatCheck()

        #expect(await check.evaluate(proposal(["ens": ".eth"])).passed == false) // no label
        #expect(await check.evaluate(proposal(["ens": "a..b.eth"])).passed == false) // empty label
        #expect(await check.evaluate(proposal(["ens": "-lead.eth"])).passed == false)
        #expect(await check.evaluate(proposal(["ens": "trail-.eth"])).passed == false)
        #expect(await check.evaluate(proposal(["ens": ""])).passed == false)
        #expect(await check.evaluate(proposal(["ens": String(repeating: "a", count: 300) + ".eth"])).passed == false)
    }

    @Test
    func chainScope() async {
        let check = ChainScopeCheck(allowed: [.ethMainnet])
        #expect(await check.evaluate(proposal(["chain": "ethereum"])).passed)
        #expect(await check.evaluate(proposal(["chain": "dogechain"])).passed == false)
        #expect(await check.evaluate(proposal([:])).passed) // absent → passes
    }

    @Test("every vocabulary for the same chain reaches the same verdict")
    func chainScopeResolvesEveryVocabulary() async {
        let check = ChainScopeCheck(allowed: [.ethMainnet])

        // Friendly alias, canonical raw value, CAIP-2, decimal id, and hex id all mean chain 1.
        for reference in ["ethereum", "eth-mainnet", "eip155:1", "1", "0x1"] {
            #expect(await check.evaluate(proposal(["chain": reference])).passed, "\(reference) should be in scope")
        }
        // A chain that resolves but is outside the allowlist is refused, and named in the detail.
        let outOfScope = await check.evaluate(proposal(["chain": "eip155:137"]))
        #expect(outOfScope.passed == false)
        #expect(outOfScope.detail == "chain out of scope: polygon-mainnet")
    }

    @Test("an unresolvable chain reference fails closed")
    func unresolvableChainFailsClosed() async {
        let check = ChainScopeCheck(allowed: [.ethMainnet])
        let result = await check.evaluate(proposal(["chain": "not-a-chain"]))

        #expect(result.passed == false)
        #expect(result.detail == "unrecognized chain reference")
    }

    @Test("an empty allowlist admits nothing")
    func emptyChainAllowlistAdmitsNothing() async {
        let check = ChainScopeCheck(allowed: [])

        #expect(await check.evaluate(proposal(["chain": "ethereum"])).passed == false)
    }

    @Test
    func contextFreshness() async {
        let check = ContextFreshnessCheck(maxAge: 300)
        #expect(await check.evaluate(proposal([
            "contextRefreshedAt": "999900",
            "freshnessEvaluatedAt": "1000000"
        ])).passed)
        #expect(await check.evaluate(proposal([
            "contextRefreshedAt": "999000",
            "freshnessEvaluatedAt": "1000000"
        ])).passed == false)
        #expect(await check.evaluate(proposal([:])).passed == false)
    }

    @Test("unparseable and future context timestamps are refused separately")
    func contextFreshnessRefusesUnparseableAndFutureTimestamps() async {
        let check = ContextFreshnessCheck(maxAge: 300)

        let unparseable = await check.evaluate(proposal([
            "contextRefreshedAt": "yesterday",
            "freshnessEvaluatedAt": "1000000"
        ]))
        #expect(unparseable.passed == false)
        #expect(unparseable.detail == "unparseable context timestamp")

        let future = await check.evaluate(proposal([
            "contextRefreshedAt": "1000600",
            "freshnessEvaluatedAt": "1000000"
        ]))
        #expect(future.passed == false)
        #expect(future.detail == "context timestamp is in the future")
    }

    @Test
    func registryRegistersAllStandardChecks() async {
        let registry = DeterministicCheckRegistry()
        let conflicts = await registry.registerStandardChecks()
        #expect(conflicts.isEmpty)
        let results = await registry.evaluate(
            ids: [StandardCheckID.addressFormat, StandardCheckID.ensNameFormat, StandardCheckID.chainInScope, StandardCheckID.contextFresh],
            for: proposal([
                "chain": "ethereum",
                "contextRefreshedAt": "1000000",
                "freshnessEvaluatedAt": "1000000"
            ])
        )
        #expect(results.allPassed)
    }

    @Test("the configuration reaches the checks it configures")
    func configurationIsApplied() async {
        let registry = DeterministicCheckRegistry()
        await registry.registerStandardChecks(
            StandardCheckConfiguration(allowedChains: [.baseMainnet], contextMaxAge: 10)
        )

        // Narrowed allowlist: mainnet is no longer in scope, Base is.
        let ethereum = await registry.evaluate(ids: [StandardCheckID.chainInScope], for: proposal(["chain": "ethereum"]))
        #expect(ethereum.allPassed == false)
        let base = await registry.evaluate(ids: [StandardCheckID.chainInScope], for: proposal(["chain": "base"]))
        #expect(base.allPassed)

        // Narrowed freshness window: 100s old is stale at maxAge 10.
        let stale = await registry.evaluate(
            ids: [StandardCheckID.contextFresh],
            for: proposal([
                "contextRefreshedAt": "999900",
                "freshnessEvaluatedAt": "1000000"
            ])
        )
        #expect(stale.allPassed == false)
    }

    @Test("every target in a serialized watchlist is validated")
    func everyWatchlistTargetIsValidated() async {
        let valid = Self.checksummedAddress
        let watchlist = """
        [{"chain":"ethereum","address":"\(valid)","ens":"vitalik.eth"},{"chain":"not-a-chain","address":"0xnothex","ens":"nope.com"}]
        """
        let candidate = proposal(["watchlist": watchlist])

        #expect(await AddressFormatCheck().evaluate(candidate).passed == false)
        #expect(await ENSNameFormatCheck().evaluate(candidate).passed == false)
        #expect(await ChainScopeCheck(allowed: [.ethMainnet]).evaluate(candidate).passed == false)
    }

    @Test("a chain or ENS name is checked even when no address accompanies it")
    func targetFieldsAreCheckedIndependentlyOfAddress() async {
        // The regression this pins: decoding required `address` before it would build a target at
        // all, so a proposal naming only a chain or only an ENS name produced zero targets and both
        // checks reported "nothing to check" on values that were right there in the parameters.
        let outOfScopeChain = await ChainScopeCheck(allowed: [.ethMainnet])
            .evaluate(proposal(["chain": "dogechain"]))
        #expect(outOfScopeChain.passed == false)
        #expect(outOfScopeChain.detail == "unrecognized chain reference")

        let badName = await ENSNameFormatCheck().evaluate(proposal(["ens": "nope.com"]))
        #expect(badName.passed == false)

        // And with an ENS name present but no address, the address check still has nothing to do.
        let noAddress = await AddressFormatCheck().evaluate(proposal(["ens": "vitalik.eth"]))
        #expect(noAddress.passed)
        #expect(noAddress.detail == "no address to check")
    }

    @Test("a present but empty chain fails closed rather than counting as absent")
    func emptyChainStringFailsClosed() async {
        let result = await ChainScopeCheck(allowed: [.ethMainnet]).evaluate(proposal(["chain": ""]))

        #expect(result.passed == false)
        #expect(result.detail == "unrecognized chain reference")
    }

    @Test("a watchlist entry missing its chain is malformed, not exempt")
    func watchlistEntryWithoutAChainIsRefused() async {
        // Decoding this leniently would hand `chain.inScope` an entry with nothing to check.
        let watchlist = """
        [{"address":"\(Self.checksummedAddress)"}]
        """
        let candidate = proposal(["watchlist": watchlist])

        let result = await ChainScopeCheck(allowed: [.ethMainnet]).evaluate(candidate)
        #expect(result.passed == false)
        #expect(result.detail == "watchlist is not valid JSON")
    }

    @Test("freshness is replayable because both time inputs are recorded")
    func contextFreshnessIsReplayable() async {
        let candidate = proposal([
            "contextRefreshedAt": "1000",
            "freshnessEvaluatedAt": "1100"
        ])
        let check = ContextFreshnessCheck(maxAge: 300)
        let first = await check.evaluate(candidate)
        let replay = await check.evaluate(candidate)

        #expect(first == replay)
    }

    @Test("a mismatched result identity fails closed under the requested ID")
    func registryEnforcesResultIdentity() async throws {
        let registry = DeterministicCheckRegistry()
        await registry.register(ClosureCheck(id: "expected") { _ in
            DeterministicCheckResult(checkID: "different", passed: true)
        })

        let results = await registry.evaluate(ids: ["expected"], for: proposal([:]))
        let result = try #require(results.first)
        #expect(result.checkID == "expected")
        #expect(result.passed == false)
    }
}

@Suite("Chain scope references")
struct ChainScopeReferenceTests {
    @Test("resolves canonical, alias, CAIP-2, decimal, and hex forms")
    func resolvesEveryForm() {
        #expect(ChainScopeReference.resolve("eth-mainnet") == .ethMainnet)
        #expect(ChainScopeReference.resolve("ethereum") == .ethMainnet)
        #expect(ChainScopeReference.resolve("  ETHEREUM  ") == .ethMainnet)
        #expect(ChainScopeReference.resolve("eip155:1") == .ethMainnet)
        #expect(ChainScopeReference.resolve("1") == .ethMainnet)
        #expect(ChainScopeReference.resolve("0x1") == .ethMainnet)
        #expect(ChainScopeReference.resolve("base") == .baseMainnet)
        #expect(ChainScopeReference.resolve("eip155:8453") == .baseMainnet)
    }

    @Test("unknown references resolve to nil rather than to a default")
    func unknownReferencesResolveToNil() {
        #expect(ChainScopeReference.resolve("") == nil)
        #expect(ChainScopeReference.resolve("   ") == nil)
        #expect(ChainScopeReference.resolve("not-a-chain") == nil)
        #expect(ChainScopeReference.resolve("eip155:999999") == nil)
        #expect(ChainScopeReference.resolve("0xzz") == nil)
    }

    @Test("a CAIP-10 account reference yields its chain part")
    func caip10AccountReferenceYieldsChain() {
        #expect(ChainScopeReference.numericChainID("eip155:1:0xd8da6bf26964af9d7eed9e03e53415d37aa96045") == 1)
        #expect(ChainScopeReference.resolve("eip155:1:0xd8da6bf26964af9d7eed9e03e53415d37aa96045") == .ethMainnet)
    }
}
