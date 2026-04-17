@testable import Auralis
import Foundation
import Testing

@Suite
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
                    recordedAt: .now
                )
            ]
        )

        #expect(!presentation.showsDetection)
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

    @Test("classified queries with no matches route into the no-results state")
    func presentationShowsNoResultsForClassifiedMisses() {
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
        #expect(presentation.content == .noResults)
    }

    @Test("matched queries render the results state")
    func presentationShowsResultsForResolvedMatches() {
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
        #expect(presentation.content == .results)
    }
}
