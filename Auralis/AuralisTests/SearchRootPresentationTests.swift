@testable import Auralis
import AuralisPrimaryModels
import Foundation
import Testing
import TokenStorage

@MainActor
struct SearchRootPresentationTests {
    @Test("empty query shows history without detection chrome")
    func presentationShowsHistoryOnlyForEmptyQuery() {
        let presentation = SearchRootView.makePresentation(
            classification: SearchQueryClassification(
                rawQuery: "",
                normalizedQuery: "",
                kind: .empty,
                localMatches: []
            ),
            historyEntries: [
                SearchHistoryEntry(
                    accountAddress: "0x1111111111111111111111111111111111111111",
                    normalizedQuery: "moonpunks",
                    query: "Moonpunks",
                    recordedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            ]
        )

        #expect(presentation.showsDetection == false)
        #expect(presentation.content == .history)
    }

    @Test("invalid input routes into the safety state")
    func presentationShowsSafetyForInvalidInput() {
        let presentation = SearchRootView.makePresentation(
            classification: SearchQueryClassification(
                rawQuery: "0x1234",
                normalizedQuery: "0x1234",
                kind: .invalidAddress,
                localMatches: []
            ),
            historyEntries: []
        )

        #expect(presentation.showsDetection)
        #expect(presentation.content == .safety)
    }

    @Test("plain text queries with no deterministic matches route into the assistant state")
    func presentationShowsAssistantForTextMisses() {
        let presentation = SearchRootView.makePresentation(
            classification: SearchQueryClassification(
                rawQuery: "surreal landscape",
                normalizedQuery: "surreal landscape",
                kind: .text,
                localMatches: []
            ),
            historyEntries: []
        )

        #expect(presentation.showsDetection)
        #expect(presentation.content == .assistant)
    }

    @Test("assistant-eligible matched queries render results and assistant state")
    func presentationShowsResultsAndAssistantForResolvedProductMatches() {
        let presentation = SearchRootView.makePresentation(
            classification: SearchQueryClassification(
                rawQuery: "moonpunks",
                normalizedQuery: "moonpunks",
                kind: .collectionName,
                localMatches: [
                    SearchLocalMatch(
                        kind: .collectionName,
                        title: "Moonpunks",
                        subtitle: Chain.ethMainnet.routingDisplayName,
                        destination: .nftCollection(
                            contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                            title: "Moonpunks",
                            chain: .ethMainnet
                        )
                    )
                ]
            ),
            historyEntries: []
        )

        #expect(presentation.showsDetection)
        #expect(presentation.content == .resultsAndAssistant)
    }

    @Test("matched product queries render plain results when the assistant is unavailable")
    func presentationShowsResultsOnlyWhenAssistantUnavailable() {
        let presentation = SearchRootView.makePresentation(
            classification: SearchQueryClassification(
                rawQuery: "moonpunks",
                normalizedQuery: "moonpunks",
                kind: .collectionName,
                localMatches: [
                    SearchLocalMatch(
                        kind: .collectionName,
                        title: "Moonpunks",
                        subtitle: Chain.ethMainnet.routingDisplayName,
                        destination: .nftCollection(
                            contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                            title: "Moonpunks",
                            chain: .ethMainnet
                        )
                    )
                ]
            ),
            historyEntries: [],
            allowsAssistant: false
        )

        #expect(presentation.showsDetection)
        #expect(presentation.content == .results)
    }

    @Test("scoped misses do not fall through to global assistant answers")
    func presentationShowsNoResultsWhenScopedProductMatchIsFilteredOut() {
        let presentation = SearchRootView.makePresentation(
            classification: SearchQueryClassification(
                rawQuery: "moonpunks",
                normalizedQuery: "moonpunks",
                kind: .collectionName,
                localMatches: []
            ),
            historyEntries: [],
            allowsAssistant: false
        )

        #expect(presentation.showsDetection)
        #expect(presentation.content == .noResults)
    }

    @Test("address matches remain deterministic without assistant state")
    func presentationShowsResultsOnlyForAddressMatches() {
        let presentation = SearchRootView.makePresentation(
            classification: SearchQueryClassification(
                rawQuery: "0x1111111111111111111111111111111111111111",
                normalizedQuery: "0x1111111111111111111111111111111111111111",
                kind: .walletAddress,
                localMatches: [
                    SearchLocalMatch(
                        kind: .account,
                        title: "Primary Wallet",
                        subtitle: "0x1111...1111",
                        destination: .profile(address: "0x1111111111111111111111111111111111111111")
                    )
                ]
            ),
            historyEntries: []
        )

        #expect(presentation.showsDetection)
        #expect(presentation.content == .results)
    }

    @Test("result scopes filter deterministic local matches")
    func resultScopesFilterDeterministicLocalMatches() {
        let classification = SearchQueryClassification(
            rawQuery: "moon",
            normalizedQuery: "moon",
            kind: .collectionName,
            localMatches: [
                SearchLocalMatch(
                    kind: .collectionName,
                    title: "Moonpunks",
                    subtitle: Chain.ethMainnet.routingDisplayName,
                    destination: .nftCollection(
                        contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                        title: "Moonpunks",
                        chain: .ethMainnet
                    )
                ),
                SearchLocalMatch(
                    kind: .tokenSymbol,
                    title: "MOON",
                    subtitle: "Moon Token",
                    destination: .token(
                        contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                        chain: .ethMainnet,
                        symbol: "MOON"
                    )
                )
            ]
        )

        let nftScoped = SearchRootView.classification(classification, applying: .nfts)
        let tokenScoped = SearchRootView.classification(classification, applying: .tokens)

        #expect(nftScoped.localMatches.map(\.kind) == [.collectionName])
        #expect(tokenScoped.localMatches.map(\.kind) == [.tokenSymbol])
    }

    @Test("token-only global search surfaces matching indexed content")
    func tokenOnlySearchSurfacesMatchingIndexedContent() {
        let index = SearchLocalIndex.make(
            nftSnapshots: [
                SearchLocalIndex.NFTSnapshot(
                    id: "nft-moonpunk",
                    name: "Moonpunk #7",
                    collectionName: "Moonpunks",
                    collectionDisplayName: nil,
                    contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    accountAddressRawValue: "0x1111111111111111111111111111111111111111",
                    networkRawValue: Chain.ethMainnet.rawValue
                )
            ],
            holdingSnapshots: [
                SearchLocalIndex.HoldingSnapshot(
                    accountAddressRawValue: "0x1111111111111111111111111111111111111111",
                    chainRawValue: Chain.ethMainnet.rawValue,
                    balanceKind: .erc20,
                    contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                    symbol: "MOON",
                    displayName: "Moon Token"
                )
            ],
            accountSnapshots: [],
            currentAccountAddress: "0x1111111111111111111111111111111111111111",
            currentChain: .ethMainnet
        )
        let classification = SearchQueryClassification(
            rawQuery: "",
            normalizedQuery: "",
            kind: .empty,
            localMatches: []
        )
        let filter = SearchFilterState(
            selectedScope: .all,
            tokens: [SearchToken(kind: .content(.tokens))],
            currentAccountAddress: "0x1111111111111111111111111111111111111111",
            currentChain: .ethMainnet
        )

        let result = SearchRootView.classification(classification, applying: filter, index: index)

        #expect(result.kind == .text)
        #expect(result.localMatches.map(\.kind) == [.tokenSymbol])
    }

    @Test("token filters narrow deterministic local matches after text classification")
    func tokenFiltersNarrowDeterministicLocalMatches() {
        let classification = SearchQueryClassification(
            rawQuery: "moon",
            normalizedQuery: "moon",
            kind: .collectionName,
            localMatches: [
                SearchLocalMatch(
                    kind: .collectionName,
                    title: "Moonpunks",
                    subtitle: Chain.ethMainnet.routingDisplayName,
                    destination: .nftCollection(
                        contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                        title: "Moonpunks",
                        chain: .ethMainnet
                    )
                ),
                SearchLocalMatch(
                    kind: .tokenSymbol,
                    title: "MOON",
                    subtitle: "Moon Token",
                    destination: .token(
                        contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                        chain: .ethMainnet,
                        symbol: "MOON"
                    )
                )
            ]
        )
        let filter = SearchFilterState(
            selectedScope: .all,
            tokens: [SearchToken(kind: .content(.tokens))],
            currentAccountAddress: nil,
            currentChain: .ethMainnet
        )

        let result = SearchRootView.classification(classification, applying: filter, index: .empty)

        #expect(result.localMatches.map(\.kind) == [.tokenSymbol])
    }

    @Test("search suggestions come from scoped indexed prefixes")
    func searchSuggestionsComeFromScopedIndexedPrefixes() {
        let index = SearchLocalIndex.make(
            nftSnapshots: [
                SearchLocalIndex.NFTSnapshot(
                    id: "nft-moonpunk",
                    name: "Moonpunk #7",
                    collectionName: "Moonpunks",
                    collectionDisplayName: nil,
                    contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    accountAddressRawValue: "0x1111111111111111111111111111111111111111",
                    networkRawValue: Chain.ethMainnet.rawValue
                )
            ],
            holdingSnapshots: [
                SearchLocalIndex.HoldingSnapshot(
                    accountAddressRawValue: "0x1111111111111111111111111111111111111111",
                    chainRawValue: Chain.ethMainnet.rawValue,
                    balanceKind: .erc20,
                    contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                    symbol: "MOON",
                    displayName: "Moon Token"
                )
            ],
            accountSnapshots: [],
            currentAccountAddress: "0x1111111111111111111111111111111111111111",
            currentChain: .ethMainnet
        )

        let allSuggestions = SearchRootView.makeSuggestions(
            query: "moo",
            index: index,
            scope: .all
        )
        let tokenSuggestions = SearchRootView.makeSuggestions(
            query: "moo",
            index: index,
            scope: .tokens
        )

        #expect(allSuggestions.map(\.completion).contains("Moonpunk #7"))
        #expect(allSuggestions.map(\.completion).contains("Moonpunks"))
        #expect(allSuggestions.map(\.completion).contains("MOON"))
        #expect(tokenSuggestions.map(\.completion) == ["MOON"])
    }

    @Test("ranked suggestions prefer prefix before word-prefix before substring")
    func rankedSuggestionsPreferPrefixBeforeWordPrefixBeforeSubstring() {
        let index = SearchLocalIndex(
            accounts: [],
            ensEntries: [],
            contracts: [],
            tokenSymbols: [],
            nftNames: [
                .init(
                    nftID: "prefix",
                    normalizedName: "moonrise signal",
                    displayName: "Moonrise Signal",
                    collectionDisplayName: "Signals"
                ),
                .init(
                    nftID: "word-prefix",
                    normalizedName: "blue moon relic",
                    displayName: "Blue Moon Relic",
                    collectionDisplayName: "Relics"
                ),
                .init(
                    nftID: "substring",
                    normalizedName: "amoon archive",
                    displayName: "Amoon Archive",
                    collectionDisplayName: "Archives"
                )
            ],
            collections: []
        )
        let suggestions = SearchRootView.makeSuggestions(
            query: "moon",
            index: index,
            filter: SearchFilterState(
                selectedScope: .all,
                tokens: [],
                currentAccountAddress: nil,
                currentChain: .ethMainnet
            ),
            historyEntries: []
        )

        #expect(suggestions.map(\.completion) == ["Moonrise Signal", "Blue Moon Relic", "Amoon Archive"])
    }
}
