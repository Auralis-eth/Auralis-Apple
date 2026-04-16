import Foundation

struct SearchQueryParser {
    func classify(query: String, index: SearchLocalIndex) -> SearchQueryClassification {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()

        guard !trimmed.isEmpty else {
            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: "",
                kind: .empty,
                localMatches: []
            )
        }

        if let normalizedAddress = trimmed.extractedEthereumAddress?.lowercased() {
            let accountMatches = index.accountMatches(address: normalizedAddress)
            let contractMatches = index.contractMatches(address: normalizedAddress)
            let combinedMatches = (accountMatches + contractMatches).prefix(6)

            let kind: SearchQueryKind
            if !accountMatches.isEmpty, contractMatches.isEmpty {
                kind = .walletAddress
            } else if accountMatches.isEmpty, !contractMatches.isEmpty {
                kind = .contractAddress
            } else {
                kind = .ambiguousAddress
            }

            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: normalizedAddress,
                kind: kind,
                localMatches: Array(combinedMatches)
            )
        }

        if Self.looksLikeAddressCandidate(trimmed) {
            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: normalized,
                kind: .invalidAddress,
                localMatches: []
            )
        }

        if Self.looksLikeENSName(trimmed) {
            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: normalized,
                kind: .ensName,
                localMatches: index.ensMatches(name: normalized)
            )
        }

        if Self.looksLikeInvalidENSCandidate(trimmed) {
            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: normalized,
                kind: .invalidENSLike,
                localMatches: []
            )
        }

        if let symbolCandidate = Self.normalizedSymbolCandidate(trimmed) {
            let symbolMatches = index.tokenSymbolMatches(symbol: symbolCandidate)
            if !symbolMatches.isEmpty {
                return SearchQueryClassification(
                    rawQuery: query,
                    normalizedQuery: normalized,
                    kind: .tokenSymbol,
                    localMatches: symbolMatches
                )
            }
        }

        let exactNameMatches = index.exactNFTNameMatches(query: normalized)
        if !exactNameMatches.isEmpty {
            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: normalized,
                kind: .nftName,
                localMatches: exactNameMatches
            )
        }

        let exactCollectionMatches = index.exactCollectionMatches(query: normalized)
        if !exactCollectionMatches.isEmpty {
            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: normalized,
                kind: .collectionName,
                localMatches: exactCollectionMatches
            )
        }

        let partialCollectionMatches = index.partialCollectionMatches(query: normalized)
        if !partialCollectionMatches.isEmpty {
            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: normalized,
                kind: .collectionName,
                localMatches: partialCollectionMatches
            )
        }

        let partialNameMatches = index.partialNFTNameMatches(query: normalized)
        if !partialNameMatches.isEmpty {
            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: normalized,
                kind: .nftName,
                localMatches: partialNameMatches
            )
        }

        return SearchQueryClassification(
            rawQuery: query,
            normalizedQuery: normalized,
            kind: .text,
            localMatches: []
        )
    }

    private static func looksLikeAddressCandidate(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("0x")
    }

    private static func looksLikeInvalidENSCandidate(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.contains(" "), trimmed.contains(".") else {
            return false
        }

        return !looksLikeENSName(trimmed)
    }

    private static func normalizedSymbolCandidate(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "),
              trimmed.range(of: #"^[A-Za-z0-9]{2,8}$"#, options: .regularExpression) != nil else {
            return nil
        }

        return trimmed.uppercased()
    }

    static func looksLikeENSName(_ candidate: String) -> Bool {
        candidate.trimmingCharacters(in: .whitespacesAndNewlines).range(
            of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.eth$"#,
            options: .regularExpression
        ) != nil
    }
}
