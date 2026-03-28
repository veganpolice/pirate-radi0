import AVFoundation

/// Plays received voice clips while ducking Spotify audio.
/// Drop-not-queue: if a clip is already playing, incoming clips are dropped.
@MainActor @Observable
final class VoiceClipPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var currentlyPlayingSender: String?
    private var audioPlayer: AVAudioPlayer?

    var isPlaying: Bool { currentlyPlayingSender != nil }

    func playClip(data: Data, senderName: String) {
        guard currentlyPlayingSender == nil else { return } // drop if busy

        do {
            // Duck Spotify while clip plays
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)

            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.play()
            self.audioPlayer = player
            self.currentlyPlayingSender = senderName
        } catch {
            print("[VoiceClipPlayer] Failed to play clip: \(error)")
            restoreAudioSession()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        Task { @MainActor in
            self.audioPlayer = nil
            self.currentlyPlayingSender = nil
            self.restoreAudioSession()
        }
    }

    private func restoreAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}
