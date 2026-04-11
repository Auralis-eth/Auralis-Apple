import Foundation
import Testing
@testable import Auralis

@Suite
struct ERC20TokenDetailPresentationTests {
    @Test("token detail uses scoped holding metadata when it is available")
    func presentationUsesHoldingMetadata() {
        let route = ERC20TokenRoute(
            contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            chain: .baseMainnet,
            symbol: "USDC"
        )
        let holding = TokenHolding(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet,
            contractAddress: route.contractAddress,
            symbol: "USDC",
            displayName: "USD Coin",
            amountDisplay: "125.00",
            balanceKind: .erc20,
            updatedAt: Date(timeIntervalSince1970: 100),
            isPlaceholder: false
        )

        let presentation = ERC20TokenDetailPresentation(route: route, holding: holding)

        #expect(presentation.title == "USD Coin")
        #expect(presentation.navigationTitle == "USD Coin")
        #expect(presentation.symbol == "USDC")
        #expect(presentation.amountDisplay == "125.00")
        #expect(presentation.chainTitle == Chain.baseMainnet.routingDisplayName)
        #expect(presentation.contractAddress == route.contractAddress)
        #expect(presentation.metadataStatus == nil)
        #expect(presentation.isAmountHidden == false)
    }

    @Test("token detail degrades honestly when holding metadata is sparse")
    func presentationDegradesCleanlyForSparseMetadata() {
        let route = ERC20TokenRoute(
            contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            chain: .ethMainnet,
            symbol: "???"
        )
        let holding = TokenHolding(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            contractAddress: route.contractAddress,
            symbol: nil,
            displayName: "Unknown Token",
            amountDisplay: "Balance unavailable",
            balanceKind: .erc20,
            updatedAt: Date(timeIntervalSince1970: 200),
            isPlaceholder: true
        )

        let presentation = ERC20TokenDetailPresentation(route: route, holding: holding)

        #expect(presentation.title == "Unknown Token")
        #expect(presentation.symbol == "???")
        #expect(presentation.isPlaceholder)
        #expect(presentation.metadataStatus == "Some token metadata is still sparse for this holding.")
        #expect(presentation.isAmountHidden == false)
    }

    @Test("token detail remains understandable when the local holding is missing")
    func presentationSupportsMissingHolding() {
        let route = ERC20TokenRoute(
            contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            chain: .ethMainnet,
            symbol: "USDC"
        )

        let presentation = ERC20TokenDetailPresentation(route: route, holding: nil)

        #expect(presentation.title == "USDC")
        #expect(presentation.amountDisplay == "Balance unavailable")
        #expect(presentation.contractAddress == route.contractAddress)
        #expect(presentation.metadataStatus == "This token route is valid, but a scoped local holding is not currently available.")
    }

    @Test("token detail keeps native-style fallback holdings understandable")
    func presentationSupportsNativeStyleFallback() {
        let route = ERC20TokenRoute(
            contractAddress: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
            chain: .ethMainnet,
            symbol: "ETH"
        )
        let holding = TokenHolding(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            contractAddress: route.contractAddress,
            symbol: "ETH",
            displayName: "Ethereum Native",
            amountDisplay: "1.25",
            balanceKind: .native,
            updatedAt: Date(timeIntervalSince1970: 300),
            isPlaceholder: false
        )

        let presentation = ERC20TokenDetailPresentation(route: route, holding: holding)

        #expect(presentation.title == "Ethereum Native")
        #expect(presentation.symbol == "ETH")
        #expect(presentation.isNativeStyleFallback)
        #expect(presentation.metadataStatus == "This screen is using a native-style holding fallback inside the token detail contract.")
    }

    @Test("token detail explains when the amount is hidden until decimals resolve")
    func presentationFlagsHiddenAmount() {
        let route = ERC20TokenRoute(
            contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            chain: .baseMainnet,
            symbol: "USDC"
        )
        let holding = TokenHolding(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet,
            contractAddress: route.contractAddress,
            symbol: "USDC",
            displayName: "USD Coin",
            amountDisplay: "Amount hidden",
            balanceKind: .erc20,
            updatedAt: Date(timeIntervalSince1970: 250),
            isPlaceholder: true
        )

        let presentation = ERC20TokenDetailPresentation(route: route, holding: holding)

        #expect(presentation.isAmountHidden)
        #expect(presentation.amountDisplay == "Amount hidden")
        #expect(presentation.metadataStatus == "Balance is hidden until token decimals load, so Auralis does not guess at base-unit values.")
    }

    @Test("token detail presentation remains stable as richer metadata arrives later")
    func presentationAcceptsLaterEnrichmentWithoutContractChange() {
        let route = ERC20TokenRoute(
            contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            chain: .baseMainnet,
            symbol: "TOK"
        )
        let holding = TokenHolding(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet,
            contractAddress: route.contractAddress,
            symbol: "TOK",
            displayName: "Token Name",
            amountDisplay: "42.00",
            balanceKind: .erc20,
            updatedAt: Date(timeIntervalSince1970: 400),
            isPlaceholder: false
        )

        let presentation = ERC20TokenDetailPresentation(route: route, holding: holding)

        #expect(presentation.title == "Token Name")
        #expect(presentation.symbol == "TOK")
        #expect(presentation.amountDisplay == "42.00")
        #expect(presentation.scopeTitle == "\(Chain.baseMainnet.routingDisplayName) token scope")
        #expect(presentation.metadataStatus == nil)
    }
}
