import Observation
import SwiftUI

/// Root presentation model for the AuraPlay Phase 1 foundation.
@Observable
@MainActor
final class AuraPlayRootModel {
    @ObservationIgnored
    let libraryRepository: any AuraPlayLibraryRepository

    @ObservationIgnored
    let playbackController: any AuraPlayPlaybackControlling

    @ObservationIgnored
    let queueCoordinator: any AuraPlayQueueCoordinating

    @ObservationIgnored
    let artworkLoader: any AuraPlayArtworkLoading

    @ObservationIgnored
    let logger: any AuraPlayLogging

    @ObservationIgnored
    let configuration: AuraPlayModuleConfiguration

    private(set) var currentAccount: EOAccount?
    private(set) var currentChain: Chain

    var libraryItemCount: Int?
    var upcomingQueueCount: Int
    var playbackHistoryCount: Int
    var currentArtworkURL: URL?
    var lastError: AuraPlayError?
    var configurationStatus: String
    var statusMessage: String

    init(
        libraryRepository: any AuraPlayLibraryRepository,
        playbackController: any AuraPlayPlaybackControlling,
        queueCoordinator: any AuraPlayQueueCoordinating,
        artworkLoader: any AuraPlayArtworkLoading,
        logger: any AuraPlayLogging,
        configuration: AuraPlayModuleConfiguration,
        currentAccount: EOAccount?,
        currentChain: Chain
    ) {
        self.libraryRepository = libraryRepository
        self.playbackController = playbackController
        self.queueCoordinator = queueCoordinator
        self.artworkLoader = artworkLoader
        self.logger = logger
        self.configuration = configuration
        self.currentAccount = currentAccount
        self.currentChain = currentChain
        self.upcomingQueueCount = 0
        self.playbackHistoryCount = 0
        self.currentArtworkURL = nil
        self.configurationStatus = Self.makeConfigurationStatus(configuration)
        self.statusMessage = "AuraPlay Phase 1 foundation is wired. Library and playback dependencies now enter through explicit seams."
    }

    var scope: AuraPlayLibraryScope {
        AuraPlayLibraryScope(
            accountAddress: currentAccount?.address,
            chain: currentChain
        )
    }

    func updateContext(
        currentAccount: EOAccount?,
        currentChain: Chain
    ) {
        let accountChanged = self.currentAccount?.address != currentAccount?.address
        let chainChanged = self.currentChain != currentChain

        guard accountChanged || chainChanged else {
            return
        }

        self.currentAccount = currentAccount
        self.currentChain = currentChain
        configurationStatus = Self.makeConfigurationStatus(configuration)
    }

    func refreshLibrarySummary() {
        logger.log(
            AuraPlayLogEvent(
                category: .library,
                level: .info,
                message: "Refreshing AuraPlay library summary for \(scope.accountAddress == nil ? "no active account" : "active account") on \(scope.chain.rawValue)"
            )
        )

        do {
            libraryItemCount = try libraryRepository.itemCount(in: scope)
            lastError = nil
        } catch {
            libraryItemCount = nil
            lastError = AuraPlayError.library(error)
            statusMessage = "AuraPlay foundation is active, but the library summary could not be loaded yet."
            logger.log(
                AuraPlayLogEvent(
                    category: .library,
                    level: .error,
                    message: lastError?.localizedDescription ?? "AuraPlay library refresh failed."
                )
            )
        }

        let queueSnapshot = queueCoordinator.snapshot()
        upcomingQueueCount = queueSnapshot.upcomingCount
        playbackHistoryCount = queueSnapshot.historyCount

        do {
            currentArtworkURL = try artworkLoader.artworkURL(for: playbackController.currentTrack)
        } catch let error as AuraPlayError {
            currentArtworkURL = nil
            lastError = error
            logger.log(
                AuraPlayLogEvent(
                    category: .artwork,
                    level: .error,
                    message: error.localizedDescription
                )
            )
        } catch {
            currentArtworkURL = nil
            let mappedError = AuraPlayError.artwork(error)
            lastError = mappedError
            logger.log(
                AuraPlayLogEvent(
                    category: .artwork,
                    level: .error,
                    message: mappedError.localizedDescription
                )
            )
        }

        if let lastError {
            statusMessage = lastError.localizedDescription
        } else if configuration.missingRequirements.isEmpty {
            statusMessage = "AuraPlay Phase 1 foundation is wired. Library, playback, queue, artwork, and config seams now enter through explicit dependencies."
        } else {
            statusMessage = "AuraPlay foundation is active, but the bundle contract still needs attention."
        }
    }

    private static func makeConfigurationStatus(_ configuration: AuraPlayModuleConfiguration) -> String {
        if configuration.missingRequirements.isEmpty {
            return "Bundle contract ready"
        }
        return configuration.missingRequirements.joined(separator: " ")
    }
}

struct AuraPlayEntryView: View {
    @Bindable var model: AuraPlayRootModel

    var body: some View {
        AuraScenicScreen(contentAlignment: .topLeading) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    AuraPill("AuraPlay", systemImage: "waveform.circle", emphasis: .accent)
                    AuraSectionHeader(
                        title: "Music Rebuild In Progress",
                        subtitle: "This root is the migration seam for the rebuilt music experience."
                    )
                }

                AuraSurfaceCard(style: .soft, cornerRadius: 28, padding: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Composition root active", systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)

                        Text(model.statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)

                        Divider()
                            .overlay(Color.white.opacity(0.08))

                        infoRow(title: "Account", value: model.currentAccount?.name ?? model.currentAccount?.address ?? "No active account")
                        infoRow(title: "Chain", value: model.currentChain.displayName)
                        infoRow(
                            title: "Indexed Library Items",
                            value: model.libraryItemCount.map(String.init) ?? "Unavailable"
                        )
                        infoRow(title: "Playback State", value: String(describing: model.playbackController.playbackState).capitalized)
                        infoRow(title: "Upcoming Queue", value: String(model.upcomingQueueCount))
                        infoRow(title: "Playback History", value: String(model.playbackHistoryCount))
                        infoRow(
                            title: "Current Artwork",
                            value: model.currentArtworkURL?.absoluteString ?? "Unavailable"
                        )
                        infoRow(title: "Bundle Contract", value: model.configurationStatus)
                    }
                }

                AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
                    Text("Next migration step: move the Library surface onto these seams before touching Now Playing or queue orchestration.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationTitle("Music")
        .task(
            id: "\(model.currentAccount?.address ?? "none")|\(model.currentChain.rawValue)"
        ) {
            model.refreshLibrarySummary()
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 124, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)

            Spacer(minLength: 0)
        }
    }
}
