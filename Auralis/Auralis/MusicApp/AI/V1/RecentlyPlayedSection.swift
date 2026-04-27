import SwiftUI

struct RecentlyPlayedSection: View {
    @ObservedObject var audioEngine: AudioEngine
    private let initialLimit: Int = 20
    @State private var isClearing = false

    private var items: [NFT] {
        audioEngine.getRecentlyPlayed(limit: initialLimit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("Recently Played", comment: "Recently Played section header"))
                    .font(.headline)
                Spacer()
                if !items.isEmpty {
                    Button(NSLocalizedString("Clear All", comment: "Clear all recently played")) { isClearing = true }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear all recently played")
                }
            }

            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("Nothing here yet—play something and it’ll show up.", comment: "Empty state for Recently Played"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items, id: \.id) { nft in
                            RecentlyPlayedMiniCard(nft: nft,
                                                   lastPlayed: audioEngine.lastPlayedDate(for: nft.id)) {
                                playTapped(nft: nft)
                            }
                            .frame(width: 160)
                            .contextMenu {
                                Button {
                                    playTapped(nft: nft)
                                } label: {
                                    Label(NSLocalizedString("Play", comment: "Play recently played item"), systemImage: "play.fill")
                                }

                                Button {
                                    startOverTapped(nft: nft)
                                } label: {
                                    Label(NSLocalizedString("Start Over", comment: "Start recently played item from beginning"), systemImage: "arrow.counterclockwise")
                                }

                                Button(role: .destructive) {
                                    audioEngine.removeFromPrevious(id: nft.id)
                                } label: {
                                    Label(NSLocalizedString("Remove from Recently Played", comment: "Remove item from recently played"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(String(format: NSLocalizedString("Recently Played, %d items", comment: "VoiceOver label for Recently Played section with count"), items.count)))
        .confirmationDialog(NSLocalizedString("Clear all recently played items?", comment: "Confirm clear recently played"),
                            isPresented: $isClearing,
                            titleVisibility: .visible) {
            Button(NSLocalizedString("Clear All", comment: "Confirm clear all"), role: .destructive) {
                audioEngine.clearPreviousHistory()
                impact()
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel"), role: .cancel) { }
        }
    }

    private func startOverTapped(nft: NFT) {
        impact()
        Task {
            if audioEngine.currentTrackNFTID == nft.id {
                try? audioEngine.seek(to: 0)
                try? audioEngine.play()
            } else {
                try? await audioEngine.loadAndPlay(nft: nft)
            }
        }
    }

    private func playTapped(nft: NFT) {
        impact()
        Task {
            if audioEngine.currentTrackNFTID == nft.id {
                try? audioEngine.resume()
            } else {
                try? await audioEngine.loadAndPlay(nft: nft)
            }
        }
    }

    private func impact() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
