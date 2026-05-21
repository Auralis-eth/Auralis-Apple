import ReceiptsCore
import ReceiptStorage
@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuralisShellCore
import Foundation
import PolicyCore
import SwiftData
import Testing
import TokenStorage

@Suite
struct NoBypassSmokeTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            EOAccount.self,
            NFT.self,
            Tag.self,
            StoredReceipt.self,
            TokenHolding.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("blocked observe actions fail with a denial receipt instead of silently executing")
    @MainActor
    func blockedObserveActionsWriteDenialReceipt() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let modeState = ModeState()

        let result = await ActionPolicyGate.attempt(
            .draftTransaction,
            modeState: modeState,
            receiptStore: receiptStore
        )

        let receipts = try await receiptStore.latest(limit: 10)

        #expect(result.isAllowed == false)
        #expect(result.userMessage == "Not available in Observe mode")
        #expect(receipts.count == 1)
        #expect(receipts.first?.trigger == "policy.denied")
        #expect(receipts.first?.details.values["action"] == ReceiptJSONValue.string("draft_transaction"))
    }

    @Test("plugin observe actions are blocked with a denial receipt")
    @MainActor
    func pluginObserveActionsWriteDenialReceipt() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let modeState = ModeState()

        let result = await ActionPolicyGate.attempt(
            .runPlugin,
            modeState: modeState,
            receiptStore: receiptStore
        )

        let receipts = try await receiptStore.latest(limit: 10)

        #expect(result.isAllowed == false)
        #expect(result.userMessage == "Not available in Observe mode")
        #expect(receipts.count == 1)
        #expect(receipts.first?.trigger == "policy.denied")
        #expect(receipts.first?.isSuccess == false)
        #expect(receipts.first?.details.values["action"] == ReceiptJSONValue.string("run_plugin"))
        #expect(receipts.first?.details.values["policy_denied"] == ReceiptJSONValue.bool(true))
        #expect(receipts.first?.details.values["policy_approved"] == ReceiptJSONValue.bool(false))
    }

    @Test("raw deep-link input is labeled while non-raw route errors are not")
    func deepLinkTrustLabelingOnlyTargetsRawInput() {
        let invalidLink = AppRouteError(
            title: "Invalid Link",
            message: "The link could not be parsed.",
            urlString: "auralis://bad-link"
        )
        let missingNFT = AppRouteError(
            title: "NFT Not Found",
            message: "The requested NFT could not be resolved for the current account.",
            urlString: nil
        )

        #expect(invalidLink.trustLabelKind == .deepLink)
        #expect(missingNFT.trustLabelKind == nil)
    }

    @Test("search-owned routing still hands detail destinations back to their owning tabs")
    func searchRoutingStillUsesOwnedTabs() {
        let router = AppRouter()

        router.showSearch()
        #expect(router.selectedTab == .search)
        #expect(router.currentRouteDepth == 0)

        router.showProfileDetail(address: "0x1111111111111111111111111111111111111111")
        #expect(router.selectedTab == .profile)
        #expect(router.profilePath == [.detail(address: "0x1111111111111111111111111111111111111111")])

        router.showERC20Token(
            contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            chain: .baseMainnet,
            symbol: "USDC"
        )
        #expect(router.selectedTab == .erc20Tokens)
        #expect(router.currentRouteDepth == 1)

        router.showNFTCollectionDetail(
            contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            title: "Moonpunks",
            chain: .ethMainnet
        )
        #expect(router.selectedTab == .nftTokens)
        #expect(
            router.nftTokensPath.last == .collection(
                contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                title: "Moonpunks",
                chain: .ethMainnet
            )
        )
    }
}
