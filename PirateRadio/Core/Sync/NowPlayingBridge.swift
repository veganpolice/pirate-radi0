import Foundation
import MediaPlayer

/// Bridges session playback state to the system Now Playing info center.
/// Shows track info on lock screen and Dynamic Island; handles remote commands.
@MainActor
final class NowPlayingBridge {
    private let sessionStore: SessionStore

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
        setupRemoteCommands()
    }

    func updateNowPlaying(track: Track, isPlaying: Bool, positionSeconds: Double) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.albumName,
            MPMediaItemPropertyPlaybackDuration: Double(track.durationMs) / 1000.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: positionSeconds,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]

        // Load album art asynchronously
        if let url = track.albumArtURL {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    info[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in await self.sessionStore.resume() }
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in await self.sessionStore.pause() }
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                if self.sessionStore.session?.isPlaying == true {
                    await self.sessionStore.pause()
                } else {
                    await self.sessionStore.resume()
                }
            }
            return .success
        }

        // Only enable DJ-specific commands
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false

        // Seeking
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                await self.sessionStore.seek(to: Int(event.positionTime * 1000))
            }
            return .success
        }
    }
}
