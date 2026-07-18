import Foundation

@MainActor
public protocol AuraPlayPlayerCommanding: Sendable {
    func togglePlayPause() async
    func skipNext() async
    func skipPrevious() async
    func seek(to seconds: TimeInterval) async
    func reorderQueueEntry(id: String, toIndex: Int) async
    func removeQueueEntry(id: String) async
    func setShuffleEnabled(_ isEnabled: Bool) async
    func cycleRepeatMode() async
    func setEQPreset(_ preset: AuraPlayEQPresetID) async
    func setCustomEQBand(index: Int, gain: Float) async
    func setNormalizationEnabled(_ isEnabled: Bool) async
    func setCrossfadeDuration(_ duration: Double) async
    func startPiP() async
    func stopPiP() async
    func restorePiP() async
    func selectSubtitle(_ title: String?) async
    func setPlaybackSpeed(_ speed: Double) async
    func toggleVideoGravity() async
    func shareCurrentItem() async
    func viewOnExplorer() async
    func copyContractAddress() async
}

public struct NoOpAuraPlayPlayerCommander: AuraPlayPlayerCommanding {
    public init() {}
    public func togglePlayPause() async {}
    public func skipNext() async {}
    public func skipPrevious() async {}
    public func seek(to seconds: TimeInterval) async {}
    public func reorderQueueEntry(id: String, toIndex: Int) async {}
    public func removeQueueEntry(id: String) async {}
    public func setShuffleEnabled(_ isEnabled: Bool) async {}
    public func cycleRepeatMode() async {}
    public func setEQPreset(_ preset: AuraPlayEQPresetID) async {}
    public func setCustomEQBand(index: Int, gain: Float) async {}
    public func setNormalizationEnabled(_ isEnabled: Bool) async {}
    public func setCrossfadeDuration(_ duration: Double) async {}
    public func startPiP() async {}
    public func stopPiP() async {}
    public func restorePiP() async {}
    public func selectSubtitle(_ title: String?) async {}
    public func setPlaybackSpeed(_ speed: Double) async {}
    public func toggleVideoGravity() async {}
    public func shareCurrentItem() async {}
    public func viewOnExplorer() async {}
    public func copyContractAddress() async {}
}
