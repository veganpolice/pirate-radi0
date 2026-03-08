import Foundation

/// No-op music source for simulator builds where Spotify SDK is unavailable.
/// Conforms to MusicSource so the full tune-to-station flow (HTTP + WebSocket + stateSync)
/// can run on the simulator with only playback mocked.
final class MockMusicSource: MusicSource, Sendable {
    func play(trackID: String, at position: Duration) async throws {
        print("[MockMusicSource] play \(trackID) at \(position)")
    }

    func pause() async throws {
        print("[MockMusicSource] pause")
    }

    func seek(to position: Duration) async throws {
        print("[MockMusicSource] seek to \(position)")
    }

    func currentPosition() async throws -> Duration {
        return .zero
    }

    var playbackStateStream: AsyncStream<PlaybackState> {
        AsyncStream { _ in }
    }
}
