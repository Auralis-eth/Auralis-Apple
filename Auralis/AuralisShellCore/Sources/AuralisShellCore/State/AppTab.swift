import Foundation

/// Lists the top-level tabs managed by the shared app router.
public enum AppTab: Hashable, CaseIterable, Sendable {
    case home
    case news
    case gas
    case music
    case receipts
    case profile
    case search
    case erc20Tokens
    case nftTokens
}
