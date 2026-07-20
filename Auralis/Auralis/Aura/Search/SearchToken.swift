import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation

struct SearchToken: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case content(SearchResultScope)
        case media(SearchMediaFilter)
        case account(address: String, displayName: String)
        case chain(Chain)
    }

    enum SearchMediaFilter: String, CaseIterable, Equatable, Sendable {
        case playable
        case audio
        case video

        var title: String {
            switch self {
            case .playable:
                return "Playable"
            case .audio:
                return "Audio"
            case .video:
                return "Video"
            }
        }
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .content(let scope):
            return "content:\(scope.rawValue)"
        case .media(let filter):
            return "media:\(filter.rawValue)"
        case .account(let address, _):
            return "account:\(address.lowercased())"
        case .chain(let chain):
            return "chain:\(chain.rawValue)"
        }
    }

    var title: String {
        switch kind {
        case .content(let scope):
            return scope.title
        case .media(let filter):
            return filter.title
        case .account(_, let displayName):
            return displayName
        case .chain(let chain):
            return chain.routingDisplayName
        }
    }

    var suggestionDetail: String {
        switch kind {
        case .content:
            return "Type"
        case .media:
            return "Media"
        case .account:
            return "Account"
        case .chain:
            return "Chain"
        }
    }
}

struct SearchFilterState: Equatable, Sendable {
    let selectedScope: SearchResultScope
    let tokens: [SearchToken]
    let currentAccountAddress: String?
    let currentChain: Chain

    var contentScopes: [SearchResultScope] {
        tokens.compactMap { token in
            guard case .content(let scope) = token.kind else {
                return nil
            }
            return scope
        }
    }

    var hasQueryIndependentFilters: Bool {
        !tokens.isEmpty || selectedScope != .all
    }

    func includes(match: SearchLocalMatch) -> Bool {
        guard selectedScope.includes(matchKind: match.kind) else {
            return false
        }

        let scopes = contentScopes
        if !scopes.isEmpty, !scopes.contains(where: { $0.includes(matchKind: match.kind) }) {
            return false
        }

        let mediaTokens = tokens.compactMap { token -> SearchToken.SearchMediaFilter? in
            guard case .media(let filter) = token.kind else {
                return nil
            }
            return filter
        }
        if !mediaTokens.isEmpty, match.kind != .musicItem {
            return false
        }

        if let accountToken = tokens.first(where: { token in
            if case .account = token.kind { return true }
            return false
        }) {
            guard case .account(let address, _) = accountToken.kind,
                  match.matchesAccount(address) else {
                return false
            }
        }

        if let chainToken = tokens.first(where: { token in
            if case .chain = token.kind { return true }
            return false
        }) {
            guard case .chain(let chain) = chainToken.kind,
                  match.matchesChain(chain) else {
                return false
            }
        }

        return true
    }
}

private extension SearchLocalMatch {
    func matchesAccount(_ address: String) -> Bool {
        let normalizedAddress = NFT.normalizedScopeComponent(address) ?? address.lowercased()
        switch destination {
        case .profile(let profileAddress):
            return (NFT.normalizedScopeComponent(profileAddress) ?? profileAddress.lowercased()) == normalizedAddress
        default:
            return true
        }
    }

    func matchesChain(_ chain: Chain) -> Bool {
        switch destination {
        case .token(_, let matchChain, _), .nftCollection(_, _, let matchChain):
            return matchChain == chain
        default:
            return true
        }
    }
}
