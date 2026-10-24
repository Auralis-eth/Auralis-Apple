@testable import Auralis
import MissionControlFeature
import Testing

/// Unit coverage for the pure mapping/formatting helpers in `AlchemyProposalSimulator` — the parts
/// of the P1-AGENT-103 transaction simulator that don't need the network. (Trust-surface behaviour:
/// a movement must never be mislabelled, and the gas-cost estimate must read cleanly.)
struct AlchemyProposalSimulatorTests {

    // MARK: - mapChange direction

    /// Without a sender address we can't attribute direction, so it must be `.unknown` rather than
    /// silently defaulting to `.outgoing`.
    @Test
    func mapChangeWithoutSenderIsUnknown() {
        let change = AlchemyProposalSimulator.SimChange(
            assetType: "NATIVE",
            changeType: "TRANSFER",
            from: "0xaaa",
            to: "0xbbb",
            amount: "0.5",
            symbol: "ETH",
            contractAddress: nil
        )

        let mapped = AlchemyProposalSimulator.mapChange(change, sender: nil)

        #expect(mapped?.direction == .unknown)
        // Falls back to `to` when direction is unknown.
        #expect(mapped?.counterparty == "0xbbb")
        #expect(mapped?.amount == "0.5")
        #expect(mapped?.symbol == "ETH")
    }

    /// An empty sender string is treated the same as no sender.
    @Test
    func mapChangeWithEmptySenderIsUnknown() {
        let change = AlchemyProposalSimulator.SimChange(
            assetType: "NATIVE", changeType: "TRANSFER", from: "0xaaa", to: "0xbbb",
            amount: "1", symbol: "ETH", contractAddress: nil
        )

        #expect(AlchemyProposalSimulator.mapChange(change, sender: "")?.direction == .unknown)
    }

    /// When the sender receives the asset (it is the `to`), the movement is incoming.
    @Test
    func mapChangeToSenderIsIncoming() {
        let change = AlchemyProposalSimulator.SimChange(
            assetType: "ERC20", changeType: "TRANSFER", from: "0xother", to: "0xME",
            amount: "10", symbol: "USDC", contractAddress: "0xtoken"
        )

        let mapped = AlchemyProposalSimulator.mapChange(change, sender: "0xme")

        #expect(mapped?.direction == .incoming)
        #expect(mapped?.counterparty == "0xother")
    }

    /// When the sender is not the recipient, the movement is outgoing.
    @Test
    func mapChangeFromSenderIsOutgoing() {
        let change = AlchemyProposalSimulator.SimChange(
            assetType: "NATIVE", changeType: "TRANSFER", from: "0xME", to: "0xother",
            amount: "0.25", symbol: "ETH", contractAddress: nil
        )

        let mapped = AlchemyProposalSimulator.mapChange(change, sender: "0xme")

        #expect(mapped?.direction == .outgoing)
        #expect(mapped?.counterparty == "0xother")
    }

    /// A movement the sender is party to *neither* side of is `.unknown`, not `.outgoing`.
    ///
    /// This is the case the original ternary got wrong: it resolved everything that was not incoming
    /// as outgoing, so the internal legs of a routed swap, a transfer between two counterparties, and
    /// refund hops all rendered as the user's money leaving — on the last screen before they sign.
    @Test
    func mapChangeBetweenThirdPartiesIsUnknown() {
        let change = AlchemyProposalSimulator.SimChange(
            assetType: "ERC20", changeType: "TRANSFER", from: "0xpool", to: "0xrouter",
            amount: "500.0", symbol: "USDC", contractAddress: "0xusdc"
        )

        let mapped = AlchemyProposalSimulator.mapChange(change, sender: "0xme")

        #expect(mapped?.direction == .unknown)
    }

    /// A change with no amount carries no information and is dropped.
    @Test
    func mapChangeWithoutAmountIsDropped() {
        let change = AlchemyProposalSimulator.SimChange(
            assetType: "NATIVE", changeType: "TRANSFER", from: "0xa", to: "0xb",
            amount: nil, symbol: "ETH", contractAddress: nil
        )

        #expect(AlchemyProposalSimulator.mapChange(change, sender: "0xa") == nil)
    }

    // MARK: - formatEth

    /// 21000 gas at 20 gwei = 0.00042 ETH, with trailing zeros trimmed.
    @Test
    func formatEthComputesAndTrims() {
        let eth = AlchemyProposalSimulator.formatEth(gasUnits: 21_000, gasPriceWei: 20_000_000_000)
        #expect(eth == "0.00042")
    }

    /// A whole-ETH result keeps a single trailing decimal rather than a bare integer.
    @Test
    func formatEthKeepsOneDecimalForWholeValues() {
        let eth = AlchemyProposalSimulator.formatEth(gasUnits: 1_000_000_000, gasPriceWei: 1_000_000_000)
        #expect(eth == "1.0")
    }

    /// A real but sub-microether fee must not render as free.
    ///
    /// Typical L2 costs land around 1e-7 ETH, which `%.6f` formatted as "0.000000" and the
    /// trailing-zero trim then reduced to "0.0" — so every Base/Arbitrum/Optimism simulation told the
    /// user the transaction cost nothing.
    @Test
    func formatEthDoesNotRoundSmallL2FeesToZero() {
        // 60,000 gas at 0.01 gwei — an ordinary Base fee, 6e-10 ETH.
        let eth = AlchemyProposalSimulator.formatEth(gasUnits: 60_000, gasPriceWei: 10_000_000)

        #expect(eth == "<0.000001")
    }

    /// A genuinely free estimate still reads as zero rather than "less than".
    @Test
    func formatEthReportsAnActualZeroAsZero() {
        #expect(AlchemyProposalSimulator.formatEth(gasUnits: 0, gasPriceWei: 20_000_000_000) == "0.0")
        #expect(AlchemyProposalSimulator.formatEth(gasUnits: 21_000, gasPriceWei: 0) == "0.0")
    }

    /// The boundary: exactly the smallest representable value still formats numerically.
    @Test
    func formatEthRendersTheDisplayPrecisionBoundary() {
        // 1e12 wei = 0.000001 ETH exactly.
        #expect(AlchemyProposalSimulator.formatEth(gasUnits: 1_000_000, gasPriceWei: 1_000_000) == "0.000001")
    }
}
