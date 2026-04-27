import Foundation

struct SearchQueryClassification: Equatable, Sendable {
    let rawQuery: String
    let normalizedQuery: String
    let kind: SearchQueryKind
    let localMatches: [SearchLocalMatch]

    var trimmedQuery: String {
        rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
