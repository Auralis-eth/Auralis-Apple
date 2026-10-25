import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation

public struct AccountSummaryPresenter: Sendable {
    public init() { }

    public func presentation(
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
            addressLine: displayAddress(inputs.address),
            chainTitle: chainTitle,
            trackedNFTLabel: trackedNFTLabel,
            lastActivityLabel: lastActivityLabel
        )
    }

    private func displayAddress(_ address: String) -> String {
        if address.count > 10 {
            let start = address.prefix(6)
            let end = address.suffix(4)
            return "\(start)...\(end)"
        }

        return address
    }
}

public struct AccountSwitcherPresenter: Sendable {
    public init() { }

    public func sortedAccounts(_ accounts: [EOAccount]) -> [EOAccount] {
        accounts.sorted { lhs, rhs in
            if lhs.lastSelectedAt != rhs.lastSelectedAt {
                switch (lhs.lastSelectedAt, rhs.lastSelectedAt) {
                case let (left?, right?):
                    return left > right
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    break
                }
            }

            if lhs.addedAt != rhs.addedAt {
                return lhs.addedAt > rhs.addedAt
            }

            return lhs.address.localizedCaseInsensitiveCompare(rhs.address) == .orderedAscending
        }
    }
}
