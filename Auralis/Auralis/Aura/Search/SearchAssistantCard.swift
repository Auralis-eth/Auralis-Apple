import SwiftUI
import AuraUI

struct SearchAssistantCard: View {
    let state: SearchAssistantState
    let onOpenMatch: (SearchLocalMatch) -> Void

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Assistant Results")
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)
                            .accessibilityAddTraits(.isHeader)

                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer(minLength: 12)

                    AuraTrustLabel(kind: .metadata)
                }

                switch state {
                case .idle:
                    Text("Ask about NFTs, tokens, receipts, wallets, or AuraPlay media in plain language.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                case .loading:
                    ProgressView()
                        .accessibilityLabel(String(localized: "Searching"))
                case .streaming(let snapshot):
                    if let answer = snapshot.answer, !answer.isEmpty {
                        Text(answer)
                            .font(.body)
                            .foregroundStyle(Color.textPrimary)
                            .textSelection(.enabled)
                    }

                    if snapshot.sections.isEmpty {
                        Text(snapshot.isStreaming ? "Gathering grounded results..." : "No grounded Spotlight results were returned.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(snapshot.sections) { section in
                                SearchAssistantSectionView(
                                    section: section,
                                    onOpenMatch: onOpenMatch
                                )
                            }
                        }
                    }
                case .unavailable(let availability):
                    AuraEmptyState(
                        eyebrow: "Assistant",
                        title: availability.title,
                        message: availability.message,
                        systemImage: "sparkle.magnifyingglass",
                        tone: .neutral
                    )
                case .failed(let message):
                    AuraEmptyState(
                        eyebrow: "Assistant",
                        title: "Search Failed",
                        message: message,
                        systemImage: "exclamationmark.triangle",
                        tone: .critical
                    )
                }
            }
            .accessibilityIdentifier(A11yID.Search.assistantResults)
        }
    }

    private var statusMessage: String {
        switch state {
        case .idle:
            return "Grounded in local Spotlight content."
        case .loading:
            return "Searching local app content."
        case .streaming(let snapshot):
            return snapshot.isStreaming ? "Updating as Spotlight returns results." : "Answer grounded by local results."
        case .unavailable:
            return "Exact search remains available."
        case .failed:
            return "Exact search remains available."
        }
    }
}

private struct SearchAssistantSectionView: View {
    let section: SearchAssistantResultSection
    let onOpenMatch: (SearchLocalMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.label.isEmpty ? "Spotlight Results" : section.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 8)

                if section.isStreaming {
                    Text("Updating")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }
            }

            switch section.payload {
            case .matches(let matches):
                SearchAssistantMatchesView(matches: matches, onOpenMatch: onOpenMatch)
            case .scoredMatches(let scoredMatches):
                SearchAssistantScoredMatchesView(scoredMatches: scoredMatches, onOpenMatch: onOpenMatch)
            case .groupedMatches(let groups):
                SearchAssistantGroupedMatchesView(groups: groups, onOpenMatch: onOpenMatch)
            case .count(let count, let header):
                SearchAssistantScalarView(
                    title: header ?? "Count",
                    value: "\(count)"
                )
            case .table(let table):
                SearchAssistantTableView(table: table)
            case .statistic(let statistic):
                SearchAssistantScalarView(
                    title: statistic.header ?? statistic.name,
                    value: statistic.value
                )
            case .text(let text, let header):
                if let header, !header.isEmpty {
                    Text(header)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

private struct SearchAssistantMatchesView: View {
    let matches: [SearchLocalMatch]
    let onOpenMatch: (SearchLocalMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(matches) { match in
                SearchAssistantMatchButton(match: match, score: nil, onOpenMatch: onOpenMatch)
            }
        }
    }
}

private struct SearchAssistantScoredMatchesView: View {
    let scoredMatches: [SearchAssistantPayload.ScoredMatch]
    let onOpenMatch: (SearchLocalMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(scoredMatches) { scoredMatch in
                SearchAssistantMatchButton(
                    match: scoredMatch.match,
                    score: scoredMatch.score,
                    onOpenMatch: onOpenMatch
                )
            }
        }
    }
}

private struct SearchAssistantGroupedMatchesView: View {
    let groups: [SearchAssistantPayload.GroupedMatches]
    let onOpenMatch: (SearchLocalMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)

                    SearchAssistantMatchesView(matches: group.matches, onOpenMatch: onOpenMatch)
                }
            }
        }
    }
}

private struct SearchAssistantMatchButton: View {
    let match: SearchLocalMatch
    let score: Double?
    let onOpenMatch: (SearchLocalMatch) -> Void

    var body: some View {
        Button {
            onOpenMatch(match)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    SearchAssistantBadge(match.kind.title)
                    Text(match.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    if let score {
                        Text(score.formatted(.number.precision(.fractionLength(2))))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Text(match.subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(match.kind.title), \(match.title)"))
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(String(localized: "Opens this result"))
        .accessibilityIdentifier(A11yID.Search.assistantMatch(id: match.id))
    }

    private var accessibilityValue: String {
        if let score {
            return String(localized: "\(match.subtitle). Relevance \(score.formatted(.number.precision(.fractionLength(2))))")
        }
        return String(localized: "\(match.subtitle)")
    }
}

private struct SearchAssistantScalarView: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SearchAssistantTableView: View {
    let table: SearchAssistantPayload.Table

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !table.columns.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    ForEach(table.columns, id: \.self) { column in
                        Text(column)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                        Text(value)
                            .font(.caption)
                            .foregroundStyle(Color.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct SearchAssistantBadge: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08), in: Capsule())
    }
}
