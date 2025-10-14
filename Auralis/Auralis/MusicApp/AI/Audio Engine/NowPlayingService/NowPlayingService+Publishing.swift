import Foundation
import MediaPlayer

@MainActor
extension NowPlayingService {
    public func updateProgress(elapsed: TimeInterval, rate: Double, duration: TimeInterval) {
        let nowUptime = ProcessInfo.processInfo.systemUptime

        let safeDuration = max(0, duration)
        let clampedElapsed: TimeInterval = {
            if safeDuration > 0 {
                return min(max(0, elapsed), safeDuration)
            } else {
                return max(0, elapsed)
            }
        }()

        let rateChanged: Bool = {
            if let last = lastPublishedRate { return abs(last - rate) > 0.0001 }
            return true
        }()
        let elapsedJumpedSignificantly: Bool = {
            if let last = lastPublishedElapsed { return abs(clampedElapsed - last) >= progressSignificantDelta }
            return true
        }()
        let shouldBypassCadence = rateChanged || elapsedJumpedSignificantly

        if !shouldBypassCadence {
            if let last = lastProgressUptime, nowUptime - last < cadence {
                return
            }
        }

        let hasDefault = info[MPNowPlayingInfoPropertyDefaultPlaybackRate] != nil

        lastProgressUptime = nowUptime
        applyNowPlaying {
            $0[MPNowPlayingInfoPropertyElapsedPlaybackTime] = clampedElapsed
            $0[MPNowPlayingInfoPropertyPlaybackRate] = rate
            if rate > 0 {
                if !hasDefault {
                    $0[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
                }
            } else {
                $0.removeValue(forKey: MPNowPlayingInfoPropertyDefaultPlaybackRate)
            }
        }

        lastPublishedElapsed = clampedElapsed
        lastPublishedRate = rate
    }

    public func setMetadata(title: String?, artist: String?, album: String? = nil, duration: TimeInterval, elapsed: TimeInterval, rate: Double, defaultRate: Double? = nil) {
        let safeDuration = max(0, duration)
        let clampedElapsed: TimeInterval = {
            if safeDuration > 0 {
                return min(max(0, elapsed), safeDuration)
            } else {
                return max(0, elapsed)
            }
        }()
        applyNowPlaying {
            $0[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
            let isLive = safeDuration <= 0
            $0[MPNowPlayingInfoPropertyIsLiveStream] = isLive
            $0[MPMediaItemPropertyTitle] = title
            $0[MPMediaItemPropertyArtist] = artist
            if let album { $0[MPMediaItemPropertyAlbumTitle] = album } else { $0.removeValue(forKey: MPMediaItemPropertyAlbumTitle) }
            $0[MPMediaItemPropertyPlaybackDuration] = isLive ? 0 : safeDuration
            $0[MPNowPlayingInfoPropertyElapsedPlaybackTime] = clampedElapsed
            $0[MPNowPlayingInfoPropertyPlaybackRate] = rate
            if rate > 0 {
                if let defaultRate {
                    $0[MPNowPlayingInfoPropertyDefaultPlaybackRate] = defaultRate
                } else {
                    $0[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
                }
            } else {
                $0.removeValue(forKey: MPNowPlayingInfoPropertyDefaultPlaybackRate)
            }
        }

        let isLive = safeDuration <= 0
        if lastIsLive != isLive {
            lastIsLive = isLive
        }

        lastPublishedElapsed = clampedElapsed
        lastPublishedRate = rate
        lastProgressUptime = ProcessInfo.processInfo.systemUptime
    }

    public func setMetadata(title: String?, artist: String?, duration: TimeInterval, elapsed: TimeInterval, rate: Double) {
        setMetadata(title: title, artist: artist, album: nil, duration: duration, elapsed: elapsed, rate: rate, defaultRate: nil)
    }
}
