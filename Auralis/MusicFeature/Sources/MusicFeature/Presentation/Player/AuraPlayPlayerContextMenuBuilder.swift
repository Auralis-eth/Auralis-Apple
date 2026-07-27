import AuraUI
import SwiftUI

/// Single context-menu construction point shared by the full player and
/// Library cells (P10-007). Both surfaces render the same share/explorer/copy
/// actions with the same accessibility identifiers.
public enum AuraPlayPlayerContextMenuBuilder {
    @ViewBuilder
    public static func playerMenu<Commander: AuraPlayPlayerCommanding>(
        item: AuraPlayPlayerItemPresentation,
        commander: Commander,
        showProvenance: (() -> Void)? = nil,
        onCopied: (@MainActor @Sendable () -> Void)? = nil
    ) -> some View {
        Button("Share", systemImage: "square.and.arrow.up") {
            Task { await commander.shareCurrentItem() }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.playerShare)

        if item.contractAddress?.isEmpty == false || item.tokenID?.isEmpty == false {
            if let showProvenance {
                Button("View On-Chain Details", systemImage: "info.circle", action: showProvenance)
                    .accessibilityIdentifier(A11yID.AuraPlay.provenancePanel)
            }

            Button("View on Explorer", systemImage: "safari") {
                Task { await commander.viewOnExplorer() }
            }
            .accessibilityIdentifier(A11yID.AuraPlay.playerViewOnExplorer)

            if item.contractAddress?.isEmpty == false {
                Button("Copy Contract", systemImage: "doc.on.doc") {
                    Task {
                        await commander.copyContractAddress()
                        onCopied?()
                    }
                }
                .accessibilityIdentifier(A11yID.AuraPlay.playerCopyContract)
            }
        }
    }

    @ViewBuilder
    public static func libraryMenu(
        isPlayable: Bool,
        open: @escaping () -> Void,
        addToPlaylist: @escaping () -> Void,
        share: (() -> Void)? = nil,
        showProvenance: (() -> Void)? = nil,
        viewOnExplorer: (() -> Void)? = nil,
        copyContract: (() -> Void)? = nil
    ) -> some View {
        Button("Open", systemImage: "arrow.up.forward.square", action: open)
        Button("Add to Playlist", systemImage: "text.badge.plus", action: addToPlaylist)
            .disabled(!isPlayable)

        if let share {
            Button("Share", systemImage: "square.and.arrow.up", action: share)
                .accessibilityIdentifier(A11yID.AuraPlay.playerShare)
        }

        if let showProvenance {
            Button("View On-Chain Details", systemImage: "info.circle", action: showProvenance)
                .accessibilityIdentifier(A11yID.AuraPlay.provenancePanel)
        }

        if let viewOnExplorer {
            Button("View on Explorer", systemImage: "safari", action: viewOnExplorer)
                .accessibilityIdentifier(A11yID.AuraPlay.playerViewOnExplorer)
        }

        if let copyContract {
            Button("Copy Contract", systemImage: "doc.on.doc", action: copyContract)
                .accessibilityIdentifier(A11yID.AuraPlay.playerCopyContract)
        }
    }
}
