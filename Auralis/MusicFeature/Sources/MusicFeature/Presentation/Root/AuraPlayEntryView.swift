import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuraUI
import Observation
import SwiftUI

/// Root presentation model for the active AuraPlay Phase 2 persistence seam.
@Observable
@MainActor
public final class AuraPlayRootModel {
    @ObservationIgnored
    let libraryRepository: any AuraPlayLibraryRepository

    @ObservationIgnored
    let librarySyncService: any AuraPlayLibrarySyncing

    @ObservationIgnored
    public let playbackController: any AuraPlayPlaybackControlling

    @ObservationIgnored
    let queueCoordinator: any AuraPlayQueueCoordinating

    @ObservationIgnored
    let artworkLoader: any AuraPlayArtworkLoading

    @ObservationIgnored
    let logger: any AuraPlayLogging

    @ObservationIgnored
    let configuration: AuraPlayModuleConfiguration

    @ObservationIgnored
    let urlResolver: URLResolver

    public private(set) var currentAccount: EOAccount?
    public private(set) var currentChain: Chain

    public var libraryItemCount: Int?
    public var upcomingQueueCount: Int
    public var playbackHistoryCount: Int
    public var currentArtworkURL: URL?
    public var lastError: AuraPlayError?
    public var configurationStatus: String
    public var statusMessage: String

    public init(
        libraryRepository: any AuraPlayLibraryRepository,
        librarySyncService: any AuraPlayLibrarySyncing,
        playbackController: any AuraPlayPlaybackControlling,
        queueCoordinator: any AuraPlayQueueCoordinating,
        artworkLoader: any AuraPlayArtworkLoading,
        logger: any AuraPlayLogging,
        configuration: AuraPlayModuleConfiguration,
        urlResolver: URLResolver,
        currentAccount: EOAccount?,
        currentChain: Chain
    ) {
        self.libraryRepository = libraryRepository
        self.librarySyncService = librarySyncService
        self.playbackController = playbackController
        self.queueCoordinator = queueCoordinator
        self.artworkLoader = artworkLoader
        self.logger = logger
        self.configuration = configuration
        self.urlResolver = urlResolver
        self.currentAccount = currentAccount
        self.currentChain = currentChain
        self.upcomingQueueCount = 0
        self.playbackHistoryCount = 0
        self.currentArtworkURL = nil
        self.configurationStatus = Self.makeConfigurationStatus(configuration)
        self.statusMessage = "AuraPlay Phase 2 persistence is wired. Wallet-scoped media now syncs into the AuraPlay store through explicit seams."
    }

    public var scope: AuraPlayLibraryScope {
        AuraPlayLibraryScope(
            accountAddress: currentAccount?.address,
            chain: currentChain
        )
    }

    public func updateContext(
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

    public func refreshLibrarySummary() async {
        logger.log(
            AuraPlayLogEvent(
                category: .library,
                level: .info,
                message: "Refreshing AuraPlay library summary for \(scope.accountAddress == nil ? "no active account" : "active account") on \(scope.chain.rawValue)"
            )
        )

        do {
            try await librarySyncService.syncLibrary(
                in: scope,
                accountName: currentAccount?.name
            )
            libraryItemCount = try libraryRepository.itemCount(in: scope)
            lastError = nil
        } catch {
            libraryItemCount = nil
            lastError = AuraPlayError.library(error)
            statusMessage = "AuraPlay persistence is active, but the library summary could not be loaded yet."
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
            currentArtworkURL = try resolvedArtworkURL(for: playbackController.currentTrack)
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
            statusMessage = "AuraPlay Phase 2 persistence is wired. Library, playback, queue, artwork, config, and SwiftData seams now enter through explicit dependencies."
        } else {
            statusMessage = "AuraPlay persistence is active, but the bundle contract still needs attention."
        }
    }

    private static func makeConfigurationStatus(_ configuration: AuraPlayModuleConfiguration) -> String {
        if configuration.missingRequirements.isEmpty {
            return "Bundle contract ready"
        }
        return configuration.missingRequirements.joined(separator: " ")
    }

    private func resolvedArtworkURL(for track: AuraPlayTrack?) throws -> URL? {
        if let imageURLString = track?.imageURLString,
           let resolvedURL = urlResolver.resolve(imageURLString) {
            return resolvedURL
        }
        return try artworkLoader.artworkURL(for: track)
    }
}

struct AuraPlayEntryView: View {
    @Bindable var model: AuraPlayRootModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    AuraPill("AuraPlay", systemImage: "waveform.circle", emphasis: .accent)
                    AuraSectionHeader(
                        title: "AuraPlay Persistence Live",
                        subtitle: "This root is the migration seam for the account-scoped persisted library."
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
                        infoRow(title: "Chain", value: model.currentChain.routingDisplayName)
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
                    Text("Known later-phase work stays deferred here: search, playlists, durable playback history, and deterministic integration fixtures.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.background.ignoresSafeArea())
        .navigationTitle("Music")
        .task(
            id: "\(model.currentAccount?.address ?? "none")|\(model.currentChain.rawValue)"
        ) {
            await model.refreshLibrarySummary()
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                infoRowTitle(title)
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? 96 : 124, alignment: .leading)

                infoRowValue(value)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                infoRowTitle(title)
                infoRowValue(value)
            }
        }
    }

    private func infoRowTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(Color.textSecondary)
    }

    private func infoRowValue(_ value: String) -> some View {
        Text(value)
            .font(.subheadline)
            .foregroundStyle(Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
