@testable import Auralis
import AccountsFeature
import AuralisPrimaryModels
import Foundation
import Testing

@Suite
struct HomeTabLogicTests {
    private let logic = HomeTabLogic()

    @Test("avatar fallback picks one of the bundled deterministic asset names")
    func avatarFallbackUsesBundledAssetRange() throws {
        let support = ProfileAvatarArtworkSupport()
        let assetName = try #require(
            support.fallbackAvatarAssetName(for: "0x1234567890abcdef1234567890abcdef12345678")
        )

        #expect(assetName.hasPrefix("testProfile-"))
        let suffix = assetName.replacingOccurrences(of: "testProfile-", with: "")
        let assetIndex = try #require(Int(suffix))
        #expect((1...4).contains(assetIndex))
    }

    @Test("avatar prompt atoms stay deterministic for the same input")
    func avatarPromptsAreDeterministic() {
        let support = ProfileAvatarArtworkSupport()
        let address = "0x1234567890abcdef1234567890abcdef12345678"

        let first = support.promptAtoms(address: address, style: .character)
        let second = support.promptAtoms(address: address, style: .character)

        #expect(first == second)
        #expect(first.isEmpty == false)
    }

    @Test("aurora prompt atoms fall back to subtle stars for invalid wallet input")
    func auroraPromptsFallbackForInvalidAddress() {
        let support = HomeAuroraArtworkSupport()
        let prompts = support.promptAtoms(
            address: "not-a-wallet",
            chainId: Chain.ethMainnet.rawValue,
            lane: .poster,
            scene: .mountain
        )

        #expect(prompts.contains("subtle star patterns"))
        #expect(prompts.contains(where: { $0.contains("digital asset chain") }))
    }

    @Test("logout clears the active selection while preserving persisted accounts")
    func logoutPlanClearsSessionWithoutDeletingRoster() {
        let plan = logic.logoutPlan()

        #expect(plan.shouldDeleteNFTs)
        #expect(plan.shouldDeleteTags)
        #expect(plan.shouldDeleteAccounts == false)
        #expect(plan.nextCurrentAddress.isEmpty)
    }

    @Test("home sparse-data state distinguishes first-run sparse and normal dashboards")
    func sparseDataStateUsesScopedLocalSignals() {
        #expect(
            logic.sparseDataState(scopedNFTCount: 0, recentActivityCount: 0) == .firstRun
        )
        #expect(
            logic.sparseDataState(scopedNFTCount: 3, recentActivityCount: 0) == .sparse
        )
        #expect(
            logic.sparseDataState(scopedNFTCount: 0, recentActivityCount: 2) == .sparse
        )
        #expect(
            logic.sparseDataState(scopedNFTCount: 3, recentActivityCount: 2) == .normal
        )
    }

    @Test("home sparse-state presentation does not appear during loading or failure conditions")
    func sparseStatePresentationDefersToLoadingAndFailure() {
        #expect(
            logic.sparseStatePresentation(
                scopedNFTCount: 0,
                recentActivityCount: 0,
                isHomeLoading: true,
                isShowingFailure: false
            ) == nil
        )
        #expect(
            logic.sparseStatePresentation(
                scopedNFTCount: 0,
                recentActivityCount: 0,
                isHomeLoading: false,
                isShowingFailure: true
            ) == nil
        )
    }

    @Test("first-run and sparse Home states map only to real existing routes")
    func sparseStatePresentationUsesRealNextActions() {
        #expect(
            logic.sparseStatePresentation(
                scopedNFTCount: 0,
                recentActivityCount: 0,
                isHomeLoading: false,
                isShowingFailure: false
            ) == HomeSparseStatePresentation(
                state: .firstRun,
                primaryAction: .openSearch,
                secondaryAction: .switchAccount
            )
        )
        #expect(
            logic.sparseStatePresentation(
                scopedNFTCount: 1,
                recentActivityCount: 0,
                isHomeLoading: false,
                isShowingFailure: false
            ) == HomeSparseStatePresentation(
                state: .sparse,
                primaryAction: .openSearch,
                secondaryAction: .openNews
            )
        )
    }

    @Test("first-run Home presentation is deterministic and clears once local data exists")
    func sparseStatePresentationClearsOnceDashboardHasData() throws {
        let firstRunPresentation = logic.sparseStatePresentation(
            scopedNFTCount: 0,
            recentActivityCount: 0,
            isHomeLoading: false,
            isShowingFailure: false
        )

        #expect(try #require(firstRunPresentation).state == .firstRun)
        #expect(try #require(firstRunPresentation).primaryAction == .openSearch)
        #expect(try #require(firstRunPresentation).secondaryAction == .switchAccount)

        let clearedPresentation = logic.sparseStatePresentation(
            scopedNFTCount: 2,
            recentActivityCount: 2,
            isHomeLoading: false,
            isShowingFailure: false
        )

        #expect(clearedPresentation == nil)
    }

    @Test("account summary presentation uses trustworthy account and scope fields and degrades cleanly")
    func accountSummaryPresentationUsesOwnedFields() throws {
        let summary = logic.accountSummaryPresentation(
            inputs: HomeAccountSummaryInputs(
                accountName: "Primary Wallet",
                address: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .baseMainnet,
                scopedNFTCount: 3,
                mostRecentActivityAt: Date(timeIntervalSince1970: 200)
            )
        )

        #expect(summary.title == "Primary Wallet")
        #expect(summary.addressLine == "0x1234...5678")
        #expect(summary.chainTitle == "Base scope")
        #expect(summary.trackedNFTLabel == "3 scoped NFTs")
        let lastActivityLabel = try #require(summary.lastActivityLabel)
        #expect(lastActivityLabel.isEmpty == false)
    }

    @Test("account summary presentation falls back cleanly when optional values are absent")
    func accountSummaryPresentationDegradesCleanly() {
        let summary = logic.accountSummaryPresentation(
            inputs: HomeAccountSummaryInputs(
                accountName: nil,
                address: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                chain: .ethMainnet,
                scopedNFTCount: 0,
                mostRecentActivityAt: nil
            )
        )

        #expect(summary.title == "Active Account")
        #expect(summary.addressLine == "0xabcd...abcd")
        #expect(summary.chainTitle == "Ethereum scope")
        #expect(summary.trackedNFTLabel == "No scoped NFTs yet")
        #expect(summary.lastActivityLabel == nil)
    }

    @Test("account summary presentation updates when account or chain scope changes")
    func accountSummaryPresentationTracksAccountAndChainSwitches() {
        let firstSummary = logic.accountSummaryPresentation(
            inputs: HomeAccountSummaryInputs(
                accountName: "Primary Wallet",
                address: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                scopedNFTCount: 2,
                mostRecentActivityAt: nil
            )
        )
        let secondSummary = logic.accountSummaryPresentation(
            inputs: HomeAccountSummaryInputs(
                accountName: "Travel Wallet",
                address: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                chain: .baseMainnet,
                scopedNFTCount: 1,
                mostRecentActivityAt: nil
            )
        )

        #expect(firstSummary.title == "Primary Wallet")
        #expect(firstSummary.chainTitle == "Ethereum scope")
        #expect(secondSummary.title == "Travel Wallet")
        #expect(secondSummary.addressLine == "0xabcd...abcd")
        #expect(secondSummary.chainTitle == "Base scope")
    }

    @Test("account summary card remains useful when richer activity data is absent")
    func accountSummaryPresentationRemainsUsefulWithoutActivity() {
        let summary = logic.accountSummaryPresentation(
            inputs: HomeAccountSummaryInputs(
                accountName: "Observe Wallet",
                address: "0x9999999999999999999999999999999999999999",
                chain: .ethMainnet,
                scopedNFTCount: 4,
                mostRecentActivityAt: nil
            )
        )

        #expect(summary.title == "Observe Wallet")
        #expect(summary.addressLine == "0x9999...9999")
        #expect(summary.chainTitle == "Ethereum scope")
        #expect(summary.trackedNFTLabel == "4 scoped NFTs")
        #expect(summary.lastActivityLabel == nil)
    }

    @Test("modules presentation keeps primary modules and shell shortcuts in intentional order")
    func modulesPresentationUsesIntentionalOrdering() throws {
        let presentation = logic.modulesPresentation(trackCount: 3)

        #expect(presentation.primary.map(\.action) == [.openMusic, .openNFTTokens])
        #expect(presentation.shortcuts.map(\.action) == [.openSearch, .openNews, .openReceipts])
        #expect(try #require(presentation.primary.first).badgeTitle == "3 local")
    }

    @Test("modules presentation promotes pinned items without inventing new destinations")
    func modulesPresentationPromotesPinnedItemsFirst() throws {
        let presentation = logic.modulesPresentation(
            trackCount: 3,
            pinnedActions: [.openReceipts, .openNFTTokens]
        )

        #expect(presentation.primary.map(\.action) == [.openNFTTokens, .openMusic])
        #expect(presentation.shortcuts.map(\.action) == [.openReceipts, .openSearch, .openNews])
        #expect(try #require(presentation.primary.first).isPinned == true)
        #expect(try #require(presentation.shortcuts.first).isPinned == true)
    }

    @Test("modules presentation stays honest when local music is still empty")
    func modulesPresentationDegradesCleanlyForSparseMusic() throws {
        let presentation = logic.modulesPresentation(trackCount: 0)

        #expect(try #require(presentation.primary.first).title == "Music")
        #expect(try #require(presentation.primary.first).subtitle == "No local music tracks yet")
        #expect(try #require(presentation.primary.first).badgeTitle == "Quiet")
        #expect(presentation.shortcuts.count == 3)
    }

    @Test("modules presentation keeps shell shortcuts usable even when the home scope is sparse")
    func modulesPresentationKeepsSparseStateRoutesReachable() {
        let sparsePresentation = logic.modulesPresentation(trackCount: 0)
        let populatedPresentation = logic.modulesPresentation(trackCount: 5)

        #expect(sparsePresentation.shortcuts.map(\.action) == [.openSearch, .openNews, .openReceipts])
        #expect(populatedPresentation.shortcuts.map(\.action) == [.openSearch, .openNews, .openReceipts])
        #expect(sparsePresentation.primary.map(\.action) == [.openMusic, .openNFTTokens])
    }

    @Test("modules presentation only exposes first-pass routes that are already real destinations")
    func modulesPresentationAvoidsPretendDestinations() {
        let presentation = logic.modulesPresentation(trackCount: 2)
        let exposedActions = Set((presentation.primary + presentation.shortcuts).map(\.action))

        #expect(exposedActions == Set([
            .openMusic,
            .openNFTTokens,
            .openSearch,
            .openNews,
            .openReceipts
        ]))
    }

    @Test("recent activity preview stays shorter than the full receipts surface")
    func recentActivityPreviewItemsUseShortHomeLimit() {
        let records = (0..<5).map { index in
            ReceiptTimelineRecord(
                id: UUID(),
                sequenceID: index,
                createdAt: Date(timeIntervalSince1970: Double(100 + index)),
                actor: .system,
                mode: .observe,
                trigger: "trigger-\(index)",
                scope: "scope-\(index)",
                summary: "summary-\(index)",
                provenance: "provenance-\(index)",
                isSuccess: index % 2 == 0,
                correlationID: nil,
                details: ReceiptPayload(values: [:])
            )
        }

        let preview = logic.recentActivityPreviewItems(records: records)

        #expect(preview.count == 3)
        #expect(preview.map(\.title) == ["summary-0", "summary-1", "summary-2"])
    }

    @Test("recent activity preview rows remain readable when receipt summary data is sparse")
    func recentActivityPreviewItemsFallbackCleanly() throws {
        let preview = logic.recentActivityPreviewItems(records: [
            ReceiptTimelineRecord(
                id: UUID(),
                sequenceID: 1,
                createdAt: Date(timeIntervalSince1970: 200),
                actor: .user,
                mode: .observe,
                trigger: "wallet.connected",
                scope: "0x1234...5678 • Ethereum",
                summary: "",
                provenance: "receipt.timeline",
                isSuccess: true,
                correlationID: nil,
                details: ReceiptPayload(values: [:])
            )
        ])

        #expect(preview.count == 1)
        let item = try #require(preview.first)
        #expect(item.title == "wallet.connected")
        #expect(item.contextLine == "0x1234...5678 • Ethereum • User")
        #expect(item.statusTitle == "Success")
    }

    @Test("recent activity preview stays empty when there is no scoped history")
    func recentActivityPreviewItemsSupportsEmptyHistory() {
        let preview = logic.recentActivityPreviewItems(records: [])

        #expect(preview.isEmpty)
    }

    @Test("recent activity preview falls back to scope when both summary and trigger are empty")
    func recentActivityPreviewItemsSupportsPartialReceiptData() throws {
        let preview = logic.recentActivityPreviewItems(records: [
            ReceiptTimelineRecord(
                id: UUID(),
                sequenceID: 2,
                createdAt: Date(timeIntervalSince1970: 300),
                actor: .system,
                mode: .observe,
                trigger: "",
                scope: "0xabcd...1234 • Base",
                summary: " ",
                provenance: "receipt.timeline",
                isSuccess: false,
                correlationID: nil,
                details: ReceiptPayload(values: [:])
            )
        ])

        #expect(preview.count == 1)
        let item = try #require(preview.first)
        #expect(item.title == "0xabcd...1234 • Base")
        #expect(item.contextLine == "0xabcd...1234 • Base • System")
        #expect(item.statusTitle == "Failed")
    }
}
