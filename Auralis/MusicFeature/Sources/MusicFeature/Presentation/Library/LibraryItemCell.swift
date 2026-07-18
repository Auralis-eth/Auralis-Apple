import AuraUI
import SwiftUI

public struct LibraryItemCell: View {
    public let viewModel: LibraryItemCellViewModel
    public let layout: LibraryLayoutMode
    public let play: () -> Void
    public let open: () -> Void
    public let addToPlaylist: () -> Void

    @Environment(\.auraPlayContextActions) private var contextActions
    @Environment(\.auraPlayExplorerResolver) private var explorerResolver

    public init(
        viewModel: LibraryItemCellViewModel,
        layout: LibraryLayoutMode,
        play: @escaping () -> Void,
        open: @escaping () -> Void,
        addToPlaylist: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.layout = layout
        self.play = play
        self.open = open
        self.addToPlaylist = addToPlaylist
    }

    public var body: some View {
        // Non-playable cells stay tappable but route to detail, never playback (P9-002).
        Button(action: viewModel.isPlayable ? play : open) {
            content
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            AuraPlayPlayerContextMenuBuilder.libraryMenu(
                isPlayable: viewModel.isPlayable,
                open: open,
                addToPlaylist: addToPlaylist,
                share: shareAction,
                viewOnExplorer: explorerAction,
                copyContract: copyAction
            )
        }
        .opacity(viewModel.isPlayable ? 1 : 0.58)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(viewModel.isPlayable ? "Starts playback" : "Media is not playable")
        .accessibilityAddTraits(viewModel.isCurrent ? [.isSelected] : [])
        .accessibilityIdentifier(A11yID.AuraPlay.libraryCell(id: viewModel.id))
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .grid:
            VStack(alignment: .leading, spacing: 8) {
                artwork
                    .aspectRatio(1, contentMode: .fit)
                labels
            }
        case .list:
            HStack(spacing: 12) {
                artwork
                    .frame(width: 64, height: 64)
                labels
                Spacer(minLength: 8)
                Image(systemName: viewModel.isPlayable ? "play.circle" : "exclamationmark.triangle")
                    .foregroundStyle(viewModel.isPlayable ? Color.secondary : Color.orange)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 76)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = viewModel.artworkURL {
            CachedAsyncImage(url: url, mediaAccessibility: .decorative)
                .scaledToFill()
                .clipShape(.rect(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.secondary.opacity(0.18))
                .overlay {
                    Image(systemName: viewModel.mediaType == "Video" ? "play.rectangle" : "music.note")
                        .accessibilityHidden(true)
                }
                .accessibilityHidden(true)
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(viewModel.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                if viewModel.isCurrent {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(Color.accent)
                        .accessibilityHidden(true)
                }
            }
            Text(viewModel.creator)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(viewModel.mediaType)
                Text(viewModel.chainBadge)
                if let duration = viewModel.duration {
                    Text(duration)
                }
            }
            .font(.caption2)
            .foregroundStyle(Color.textSecondary.opacity(0.78))
        }
    }

    private var explorerURL: URL? {
        explorerResolver?.nftURL(viewModel.chain, viewModel.contractAddress, viewModel.tokenID)
    }

    private var shareAction: (() -> Void)? {
        guard let contextActions else { return nil }
        let viewModel = viewModel
        let url = explorerURL
        return {
            Task {
                await contextActions.share(
                    AuraPlayShareRequest(
                        text: [viewModel.title, viewModel.creator, viewModel.collection]
                            .filter { !$0.isEmpty }
                            .joined(separator: " - "),
                        url: url,
                        artworkURLString: viewModel.artworkURLString
                    )
                )
            }
        }
    }

    private var explorerAction: (() -> Void)? {
        guard let contextActions, let url = explorerURL else { return nil }
        return {
            Task { await contextActions.open(url) }
        }
    }

    private var copyAction: (() -> Void)? {
        guard let contextActions, let contractAddress = viewModel.contractAddress, !contractAddress.isEmpty else {
            return nil
        }
        return {
            Task { await contextActions.copy(contractAddress) }
        }
    }

    private var accessibilityLabel: String {
        var parts = [
            viewModel.title,
            viewModel.creator,
            viewModel.mediaType,
            viewModel.collection,
            viewModel.chainBadge
        ]
        if let duration = viewModel.duration {
            parts.append(duration)
        }
        if !viewModel.isPlayable {
            parts.append("Not playable")
        }
        if viewModel.isCurrent {
            parts.append("Now playing")
        }
        return parts.joined(separator: ", ")
    }
}
