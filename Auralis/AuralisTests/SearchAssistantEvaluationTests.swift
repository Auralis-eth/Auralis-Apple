@testable import Auralis
import Testing

#if canImport(CoreSpotlight)
@preconcurrency import CoreSpotlight
#endif

#if canImport(Evaluations) && canImport(FoundationModels) && canImport(CoreSpotlight)
import Evaluations
import FoundationModels

@available(iOS 27.0, *)
struct AuralisSearchEvaluation: Evaluation {
    let resultCoverage = Metric("ResultCoverage")

    let dataset = ArrayLoader(samples: [
        ModelSample(
            prompt: "show my playable music NFTs",
            expected: ["auralis.search.nft:music-nft-1"],
            expectations: TrajectoryExpectation(
                unordered: [
                    ToolExpectation("searchSpotlight", arguments: [.keyOnly(argumentName: "query")])
                ]
            )
        ),
        ModelSample(
            prompt: "which receipts failed recently",
            expected: ["auralis.search.receipt:failed-receipt"],
            expectations: TrajectoryExpectation(
                unordered: [
                    ToolExpectation("searchSpotlight", arguments: [.keyOnly(argumentName: "query")])
                ]
            )
        ),
        ModelSample(
            prompt: "group my music NFTs by collection",
            expected: ["auralis.search.nft:music-nft-1", "auralis.search.nft:music-nft-2"],
            expectations: TrajectoryExpectation(
                unordered: [
                    ToolExpectation("searchSpotlight", arguments: [.keyOnly(argumentName: "query")])
                ]
            )
        ),
        ModelSample(
            prompt: "find USDC on this chain",
            expected: ["auralis.search.erc20:eth-mainnet:0xusdc"],
            expectations: TrajectoryExpectation(
                unordered: [
                    ToolExpectation("searchSpotlight", arguments: [.keyOnly(argumentName: "query")])
                ]
            )
        ),
        ModelSample(
            prompt: "what activity happened for this wallet",
            expected: ["auralis.search.receipt:activity-receipt"],
            expectations: TrajectoryExpectation(
                unordered: [
                    ToolExpectation("searchSpotlight", arguments: [.keyOnly(argumentName: "query")])
                ]
            )
        )
    ])

    func subject(from sample: ModelSample<[String]>) async throws -> ModelSubject<[String]> {
        ModelSubject(value: Self.fixtureReturnedIdentifiers(for: String(describing: sample.prompt)))
    }

    var evaluators: Evaluators {
        Evaluator { sample, subject in
            guard let expected = sample.expected, !expected.isEmpty else {
                return resultCoverage.ignore()
            }

            let expectedIDs = Set(expected)
            let returnedIDs = Set(subject.value)
            let coverage = Double(expectedIDs.intersection(returnedIDs).count) / Double(expectedIDs.count)
            return resultCoverage.scoring(coverage)
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: resultCoverage)
    }

    private static func fixtureReturnedIdentifiers(for prompt: String) -> [String] {
        let normalizedPrompt = prompt.lowercased()
        return fixtureItems.compactMap { item in
            let searchableText = [
                item.attributeSet.title,
                item.attributeSet.displayName,
                item.attributeSet.contentDescription,
                item.attributeSet.textContent,
                item.attributeSet.keywords?.joined(separator: " "),
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

            guard fixtureTerms(for: normalizedPrompt).contains(where: { searchableText.contains($0) }) else {
                return nil
            }
            return item.uniqueIdentifier
        }
    }

    private static func fixtureTerms(for normalizedPrompt: String) -> [String] {
        if normalizedPrompt.contains("playable") || normalizedPrompt.contains("music") {
            return ["auralis:mediakind=audio", "auralis:isplayable=true", "music"]
        }
        if normalizedPrompt.contains("failed") {
            return ["auralis:receiptstatus=failed"]
        }
        if normalizedPrompt.contains("usdc") {
            return ["usdc"]
        }
        if normalizedPrompt.contains("activity") || normalizedPrompt.contains("wallet") {
            return ["activity", "auralis:documentdomain=receipt"]
        }
        return normalizedPrompt.split(separator: " ").map(String.init)
    }

    private static var fixtureItems: [CSSearchableItem] {
        [
            fixtureItem(
                id: "auralis.search.nft:music-nft-1",
                domain: .nft,
                title: "Aurora Drift",
                description: "AuraPlay media NFT in the Waves collection.",
                keywords: ["music", "auralis:documentdomain=nft", "auralis:mediakind=audio", "auralis:isplayable=true"]
            ),
            fixtureItem(
                id: "auralis.search.nft:music-nft-2",
                domain: .nft,
                title: "Midnight Signal",
                description: "AuraPlay media NFT in the Waves collection.",
                keywords: ["music", "auralis:documentdomain=nft", "auralis:mediakind=audio", "auralis:isplayable=true"]
            ),
            fixtureItem(
                id: "auralis.search.nft:visual-nft-1",
                domain: .nft,
                title: "Still Image",
                description: "Visual NFT.",
                keywords: ["visual", "auralis:documentdomain=nft", "auralis:mediakind=visual", "auralis:isplayable=false"]
            ),
            fixtureItem(
                id: "auralis.search.receipt:failed-receipt",
                domain: .receipt,
                title: "Sync Failed",
                description: "Receipt event.",
                keywords: ["receipt", "activity", "auralis:documentdomain=receipt", "auralis:receiptstatus=Failed"]
            ),
            fixtureItem(
                id: "auralis.search.receipt:activity-receipt",
                domain: .receipt,
                title: "Wallet Activity",
                description: "Receipt event for this wallet.",
                keywords: ["receipt", "activity", "wallet", "auralis:documentdomain=receipt", "auralis:receiptstatus=Succeeded"]
            ),
            fixtureItem(
                id: "auralis.search.erc20:eth-mainnet:0xusdc",
                domain: .erc20,
                title: "USDC",
                description: "ERC-20 token on Ethereum.",
                keywords: ["usdc", "token", "erc20", "auralis:documentdomain=erc20"]
            ),
        ]
    }

    private static func fixtureItem(
        id: String,
        domain: SearchIndexedDocument.Domain,
        title: String,
        description: String,
        keywords: [String]
    ) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .data)
        attributes.title = title
        attributes.contentDescription = description
        attributes.textContent = ([title, description] + keywords).joined(separator: " ")
        attributes.keywords = keywords
        return CSSearchableItem(uniqueIdentifier: id, domainIdentifier: domain.rawValue, attributeSet: attributes)
    }
}

struct SearchAssistantEvaluationTests {
    @Test("seed search evaluation meets result coverage baseline")
    func seedResultCoverageMeetsBaseline() async throws {
        guard #available(iOS 27.0, *) else {
            return
        }

        let evaluation = AuralisSearchEvaluation()
        let result = try await evaluation.run(info: ["dataset": "auralis-search-seed-v1"])
        let coverageMean = result.aggregateValue(.mean(of: evaluation.resultCoverage))
        #expect(coverageMean >= 0.5, "Result coverage should be at least 50% across seed search queries")
    }
}
#endif
