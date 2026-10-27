import AVFoundation
import Foundation

public enum AuraPlaybackRouteMode: String, Equatable, Sendable {
    case customEngine
    case systemAirPlay
}

public enum AuraSpatialAudioPolicy: String, Equatable, Sendable {
    case none
    case monoAndStereo
    case multichannel
    case monoStereoAndMultichannel

    var avFoundationFormats: AVAudioSpatializationFormats {
        switch self {
        case .none:
            AVAudioSpatializationFormats(rawValue: 0)
        case .monoAndStereo:
            .monoAndStereo
        case .multichannel:
            .multichannel
        case .monoStereoAndMultichannel:
            .monoStereoAndMultichannel
        }
    }
}

public struct AirPlayQueuePlayerItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let url: URL
    public let title: String
    public let artist: String?
    public let duration: TimeInterval?
    public let artworkData: Data?

    public init(
        id: String,
        url: URL,
        title: String,
        artist: String? = nil,
        duration: TimeInterval? = nil,
        artworkData: Data? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.duration = duration
        self.artworkData = artworkData
    }
}

public struct AirPlayQueuePlayerState: Equatable, Sendable {
    public let routeMode: AuraPlaybackRouteMode
    public let queuedItemIDs: [String]
    public let currentItemID: String?
    public let playbackRate: Double
    public let spatialAudioPolicy: AuraSpatialAudioPolicy

    public init(
        routeMode: AuraPlaybackRouteMode,
        queuedItemIDs: [String],
        currentItemID: String?,
        playbackRate: Double,
        spatialAudioPolicy: AuraSpatialAudioPolicy
    ) {
        self.routeMode = routeMode
        self.queuedItemIDs = queuedItemIDs
        self.currentItemID = currentItemID
        self.playbackRate = playbackRate
        self.spatialAudioPolicy = spatialAudioPolicy
    }
}

@MainActor
public protocol SystemAudioRoutePlaying: AnyObject {
    var state: AirPlayQueuePlayerState { get }

    func loadQueue(_ items: [AirPlayQueuePlayerItem], startAtID: String?) async
    func play() async
    func pause() async
    func stop() async
    func seek(to time: TimeInterval) async
    func advanceToNext() async
    func updateSpatialAudioPolicy(_ policy: AuraSpatialAudioPolicy)
    func bindRemoteCommands(_ remoteCommands: RemoteCommandPublishing)
}

@MainActor
public final class AirPlayQueuePlayerController: SystemAudioRoutePlaying, MediaTransportControlling {
    private let player: AVQueuePlayer
    private let nowPlayingPublisher: NowPlayingPublishing?
    private let notificationCenter: NotificationCenter
    private var queuedItems: [AirPlayQueuePlayerItem] = []
    private var playerItemsByID: [String: AVPlayerItem] = [:]
    private var idsByPlayerItem: [ObjectIdentifier: String] = [:]
    private var remoteCommandTask: Task<Void, Never>?
    private var itemEndObserver: NotificationObserverToken?
    private var spatialAudioPolicy: AuraSpatialAudioPolicy

    public init(
        player: AVQueuePlayer = AVQueuePlayer(),
        nowPlayingPublisher: NowPlayingPublishing? = nil,
        notificationCenter: NotificationCenter = .default,
        spatialAudioPolicy: AuraSpatialAudioPolicy = .monoStereoAndMultichannel
    ) {
        self.player = player
        self.nowPlayingPublisher = nowPlayingPublisher
        self.notificationCenter = notificationCenter
        self.spatialAudioPolicy = spatialAudioPolicy
        self.player.actionAtItemEnd = .advance
        self.player.automaticallyWaitsToMinimizeStalling = true
        let itemEndObserver = notificationCenter.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let playerItem = notification.object as? AVPlayerItem else {
                return
            }
            let playerItemID = ObjectIdentifier(playerItem)
            Task { @MainActor [weak self, playerItemID] in
                guard let endedID = self?.idsByPlayerItem[playerItemID] else {
                    return
                }
                await self?.handlePlayerItemDidPlayToEnd(itemID: endedID)
            }
        }
        self.itemEndObserver = NotificationObserverToken(itemEndObserver)
    }

    deinit {
        remoteCommandTask?.cancel()
        if let itemEndObserver {
            notificationCenter.removeObserver(itemEndObserver.token)
        }
    }

    public var state: AirPlayQueuePlayerState {
        AirPlayQueuePlayerState(
            routeMode: .systemAirPlay,
            queuedItemIDs: queuedItems.map(\.id),
            currentItemID: currentItemID,
            playbackRate: Double(player.rate),
            spatialAudioPolicy: spatialAudioPolicy
        )
    }

    public var isPlaying: Bool {
        player.rate != 0
    }

    public func loadQueue(_ items: [AirPlayQueuePlayerItem], startAtID: String? = nil) async {
        player.pause()
        player.removeAllItems()
        playerItemsByID.removeAll()
        idsByPlayerItem.removeAll()

        let startIndex = startAtID.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        queuedItems = Array(items.dropFirst(startIndex))

        for item in queuedItems {
            let playerItem = makePlayerItem(for: item)
            playerItemsByID[item.id] = playerItem
            idsByPlayerItem[ObjectIdentifier(playerItem)] = item.id
            player.insert(playerItem, after: nil)
        }

        await publishNowPlaying(playbackRate: 0)
    }

    public func play() async {
        player.play()
        await publishNowPlaying(playbackRate: Double(player.rate == 0 ? 1 : player.rate))
    }

    public func pause() async {
        player.pause()
        await publishNowPlaying(playbackRate: 0)
    }

    public func stop() async {
        player.pause()
        await seek(to: 0)
        await publishNowPlaying(playbackRate: 0)
    }

    public func seek(to time: TimeInterval) async {
        let target = CMTime(seconds: time, preferredTimescale: 600)
        await withCheckedContinuation { continuation in
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                continuation.resume()
            }
        }
        await publishNowPlaying(playbackRate: Double(player.rate))
    }

    public func advanceToNext() async {
        guard !queuedItems.isEmpty else {
            return
        }

        player.advanceToNextItem()
        removeQueuedItemsThroughCurrentItem()
        await publishNowPlaying(playbackRate: Double(player.rate))
    }

    public func updateSpatialAudioPolicy(_ policy: AuraSpatialAudioPolicy) {
        spatialAudioPolicy = policy
        for item in playerItemsByID.values {
            item.allowedAudioSpatializationFormats = policy.avFoundationFormats
        }
    }

    public func bindRemoteCommands(_ remoteCommands: RemoteCommandPublishing) {
        remoteCommandTask?.cancel()
        // Subscribe before spawning the task so commands yielded in the gap are buffered, not dropped.
        let events = remoteCommands.events
        remoteCommandTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else {
                    return
                }
                await self?.handleRemoteCommand(event)
            }
        }
    }

    func debugAllowedSpatializationFormats(for itemID: String) -> AVAudioSpatializationFormats? {
        playerItemsByID[itemID]?.allowedAudioSpatializationFormats
    }

    private var currentItemID: String? {
        guard let currentItem = player.currentItem else {
            return queuedItems.first?.id
        }
        return idsByPlayerItem[ObjectIdentifier(currentItem)] ?? queuedItems.first?.id
    }

    private var currentQueueItem: AirPlayQueuePlayerItem? {
        guard let currentItemID else {
            return queuedItems.first
        }
        return queuedItems.first { $0.id == currentItemID }
    }

    private func makePlayerItem(for item: AirPlayQueuePlayerItem) -> AVPlayerItem {
        let playerItem = AVPlayerItem(asset: AVURLAsset(url: item.url))
        playerItem.allowedAudioSpatializationFormats = spatialAudioPolicy.avFoundationFormats
        return playerItem
    }

    private func handleRemoteCommand(_ event: RemoteCommandEvent) async {
        await event.dispatch(to: self)
    }

    private func handlePlayerItemDidPlayToEnd(itemID: String) async {
        removeQueuedItemsThrough(itemID: itemID)
        await publishNowPlaying(playbackRate: Double(player.rate))
    }

    private func removeQueuedItemsThroughCurrentItem() {
        guard let currentItem = player.currentItem else {
            if !queuedItems.isEmpty {
                let removed = queuedItems.removeFirst()
                removePlayerItemMetadata(for: removed.id)
            }
            return
        }

        removeQueuedItemsBefore(playerItem: currentItem)
    }

    private func removeQueuedItemsThrough(itemID: String) {
        if let endedIndex = queuedItems.firstIndex(where: { $0.id == itemID }) {
            let removedItems = queuedItems.prefix(through: endedIndex)
            for item in removedItems {
                removePlayerItemMetadata(for: item.id)
            }
            queuedItems.removeFirst(endedIndex + 1)
        }
    }

    private func removeQueuedItemsBefore(playerItem: AVPlayerItem) {
        guard
            let currentID = idsByPlayerItem[ObjectIdentifier(playerItem)],
            let currentIndex = queuedItems.firstIndex(where: { $0.id == currentID }),
            currentIndex > 0
        else {
            return
        }

        let removedItems = queuedItems.prefix(currentIndex)
        for item in removedItems {
            removePlayerItemMetadata(for: item.id)
        }
        queuedItems.removeFirst(currentIndex)
    }

    private func removePlayerItemMetadata(for id: String) {
        if let playerItem = playerItemsByID.removeValue(forKey: id) {
            idsByPlayerItem.removeValue(forKey: ObjectIdentifier(playerItem))
        }
    }

    public var currentTime: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    public func next() async {
        await advanceToNext()
    }

    public func previous() async {
        await seek(to: 0)
    }

    private func publishNowPlaying(playbackRate: Double) async {
        guard let nowPlayingPublisher, let item = currentQueueItem else {
            return
        }

        await nowPlayingPublisher.update(NowPlayingState(
            title: item.title,
            artist: item.artist,
            artworkData: item.artworkData,
            duration: item.duration,
            elapsedTime: currentTime,
            playbackRate: playbackRate,
            mediaType: .audio
        ))
    }
}

private final class NotificationObserverToken: @unchecked Sendable {
    let token: NSObjectProtocol

    init(_ token: NSObjectProtocol) {
        self.token = token
    }
}
