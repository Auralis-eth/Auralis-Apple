import Foundation
import MediaPlayer

@MainActor
extension PlaybackController {
    func setupRemoteCommands() {
        // Ensure idempotent registration across controller lifecycles
        if remoteCommandsRegistered {
            updateRemoteCommandStates()
            return
        }

        let center = MPRemoteCommandCenter.shared()

        let playToken = center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        remoteCommandTokens.append((command: center.playCommand, token: playToken))

        let pauseToken = center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        remoteCommandTokens.append((command: center.pauseCommand, token: pauseToken))

        let nextToken = center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.playNext() }
            return .success
        }
        remoteCommandTokens.append((command: center.nextTrackCommand, token: nextToken))

        let prevToken = center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.playPrevious() }
            return .success
        }
        remoteCommandTokens.append((command: center.previousTrackCommand, token: prevToken))

        let scrubToken = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: e.positionTime) }
            return .success
        }
        remoteCommandTokens.append((command: center.changePlaybackPositionCommand, token: scrubToken))

        remoteCommandsRegistered = true
        updateRemoteCommandStates()
    }

    func updateRemoteCommandStates() {
        let center = MPRemoteCommandCenter.shared()
        // Play is enabled when not already playing and we have something to play
        center.playCommand.isEnabled = (snapshot.state != .playing) && (currentFile != nil || queue.peekNext() != nil)
        // Pause is enabled only when currently playing
        center.pauseCommand.isEnabled = (snapshot.state == .playing)
        // Next/previous reflect queue and elapsed logic
        center.nextTrackCommand.isEnabled = snapshot.canSkipNext
        center.previousTrackCommand.isEnabled = snapshot.canSkipPrevious
        // Scrubbing only when there is a current or loaded track
        center.changePlaybackPositionCommand.isEnabled = (snapshot.track != nil)
    }

    func clearNowPlaying() {
        // Neutralize metadata/artwork/progress to avoid stale system surfaces
        nowPlaying.setMetadata(title: nil, artist: nil, duration: 0, elapsed: 0, rate: 0)
        nowPlaying.setArtwork(from: nil)
        nowPlaying.updateProgress(elapsed: 0, rate: 0, duration: 0)
    }

    func pushNowPlaying() {
        let rate = snapshot.state == .playing ? 1.0 : 0.0
        nowPlaying.setMetadata(title: snapshot.track?.title, artist: snapshot.track?.artist, duration: snapshot.track?.duration ?? 0, elapsed: currentTime(), rate: rate)
        nowPlaying.setArtwork(from: snapshot.track?.imageUrl)
        nowPlaying.updateProgress(elapsed: currentTime(), rate: rate, duration: snapshot.track?.duration ?? 0)
    }
}
