import Foundation

struct HomeTabLogic {
    func logoutPlan() -> HomeLogoutPlan {
        HomeLogoutPlan(
            shouldDeleteNFTs: true,
            shouldDeleteAccounts: false,
            shouldDeleteTags: true,
            nextCurrentAddress: ""
        )
    }

    func sparseDataState(
        scopedNFTCount: Int,
        recentActivityCount: Int
    ) -> HomeSparseDataState {
        if scopedNFTCount == 0 && recentActivityCount == 0 {
            return .firstRun
        }

        if scopedNFTCount == 0 || recentActivityCount == 0 {
            return .sparse
        }

        return .normal
    }

    func sparseStatePresentation(
        scopedNFTCount: Int,
        recentActivityCount: Int,
        isHomeLoading: Bool,
        isShowingFailure: Bool
    ) -> HomeSparseStatePresentation? {
        guard !isHomeLoading, !isShowingFailure else {
            return nil
        }

        switch sparseDataState(
            scopedNFTCount: scopedNFTCount,
            recentActivityCount: recentActivityCount
        ) {
        case .firstRun:
            return HomeSparseStatePresentation(
                state: .firstRun,
                primaryAction: .openSearch,
                secondaryAction: .switchAccount
            )
        case .sparse:
            return HomeSparseStatePresentation(
                state: .sparse,
                primaryAction: .openSearch,
                secondaryAction: .openNews
            )
        case .normal:
            return nil
        }
    }

    func accountSummaryPresentation(
        currentAccount: EOAccount?,
        currentAddress: String,
        currentChain: Chain,
        scopedNFTCount: Int
    ) -> HomeAccountSummaryPresentation {
        accountSummaryPresentation(
            inputs: HomeAccountSummaryInputs(
                accountName: currentAccount?.name,
                address: currentAccount?.address ?? currentAddress,
                chain: currentChain,
                scopedNFTCount: scopedNFTCount,
                mostRecentActivityAt: currentAccount?.mostRecentActivityAt
            )
        )
    }

    func accountSummaryPresentation(
        inputs: HomeAccountSummaryInputs
    ) -> HomeAccountSummaryPresentation {
        let resolvedTitle = inputs.accountName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (resolvedTitle?.isEmpty == false ? resolvedTitle : nil) ?? "Active Account"
        let chainTitle = "\(inputs.chain.routingDisplayName) scope"
        let trackedNFTLabel = inputs.scopedNFTCount == 0
            ? "No scoped NFTs yet"
            : "\(inputs.scopedNFTCount) scoped NFT\(inputs.scopedNFTCount == 1 ? "" : "s")"

        let lastActivityLabel = inputs.mostRecentActivityAt.map {
            "Last active \($0.formatted(date: .abbreviated, time: .omitted))"
        }

        return HomeAccountSummaryPresentation(
            title: title,
            addressLine: inputs.address.displayAddress,
            chainTitle: chainTitle,
            trackedNFTLabel: trackedNFTLabel,
            lastActivityLabel: lastActivityLabel
        )
    }

    func modulesPresentation(
        trackCount: Int,
        pinnedActions: Set<HomeLauncherAction> = []
    ) -> HomeModulesPresentation {
        let primary = [
            HomeLauncherItem(
                action: .openMusic,
                title: "Music",
                subtitle: trackCount > 0
                    ? "Local music ready: \(trackCount) track\(trackCount == 1 ? "" : "s")"
                    : "No local music tracks yet",
                badgeTitle: trackCount > 0 ? "\(trackCount) local" : "Quiet",
                systemImage: "play.fill",
                buttonTitle: "Open player",
                isPinned: pinnedActions.contains(.openMusic)
            ),
            HomeLauncherItem(
                action: .openNFTTokens,
                title: "NFT Tokens",
                subtitle: "Browse NFT tokens and jump into detail",
                badgeTitle: "Library",
                systemImage: "square.stack",
                buttonTitle: "Open tokens",
                isPinned: pinnedActions.contains(.openNFTTokens)
            )
        ]
        let shortcuts = [
            HomeLauncherItem(
                action: .openSearch,
                title: "Search",
                subtitle: "Open the global search tab",
                badgeTitle: "Shell",
                systemImage: "magnifyingglass",
                buttonTitle: "Open Search",
                isPinned: pinnedActions.contains(.openSearch)
            ),
            HomeLauncherItem(
                action: .openNews,
                title: "News Feed",
                subtitle: "Jump to the live news surface",
                badgeTitle: "Shell",
                systemImage: "bubble.right",
                buttonTitle: "Open News Feed",
                isPinned: pinnedActions.contains(.openNews)
            ),
            HomeLauncherItem(
                action: .openReceipts,
                title: "Receipts",
                subtitle: "Review local scoped activity",
                badgeTitle: "Shell",
                systemImage: "doc.text",
                buttonTitle: "Open Receipts",
                isPinned: pinnedActions.contains(.openReceipts)
            )
        ]

        return HomeModulesPresentation(
            primary: orderedByPinned(primary),
            shortcuts: orderedByPinned(shortcuts)
        )
    }

    private func orderedByPinned(_ items: [HomeLauncherItem]) -> [HomeLauncherItem] {
        let indexedItems = Array(items.enumerated())
        return indexedItems
            .sorted { lhs, rhs in
                if lhs.element.isPinned != rhs.element.isPinned {
                    return lhs.element.isPinned && !rhs.element.isPinned
                }

                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func recentActivityPreviewItems(
        records: [ReceiptTimelineRecord],
        limit: Int = 3
    ) -> [HomeRecentActivityPreviewItem] {
        Array(records.prefix(limit)).map { record in
            let trimmedSummary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTrigger = record.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmedSummary.isEmpty ? trimmedTrigger : trimmedSummary
            let detailLine: String

            if !trimmedTrigger.isEmpty, trimmedTrigger != title {
                detailLine = "\(trimmedTrigger) • \(record.createdAt.formatted(date: .omitted, time: .shortened))"
            } else {
                detailLine = "\(record.createdAt.formatted(date: .omitted, time: .shortened)) • \(record.actorTitle)"
            }

            return HomeRecentActivityPreviewItem(
                id: record.id,
                title: title.isEmpty ? record.scope : title,
                detailLine: detailLine,
                contextLine: "\(record.scope) • \(record.actorTitle)",
                statusTitle: record.statusTitle,
                isSuccess: record.isSuccess
            )
        }
    }
}
