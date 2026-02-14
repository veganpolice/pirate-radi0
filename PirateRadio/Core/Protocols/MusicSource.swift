import Foundation

/// Playback state reported by a music source.
struct PlaybackState: Sendable, Equatable {
    let trackID: String?
    let isPlaying: Bool
    let positionSeconds: Double
    let timestamp: UInt64 // NTP timestamp when this state was captured
}

/// Abstracts music playback for testability and future multi-source support.
/// The sync engine depends on this protocol, never on SpotifyPlayer directly.
protocol MusicSource: Sendable {
    /// Start playing a track at the given position.
    func play(trackID: String, at position: Duration) async throws

    /// Pause playback.
    func pause() async throws

    /// Seek to a position in the current track.
    func seek(to position: Duration) async throws

    /// Get the current playback position.
    func currentPosition() async throws -> Duration

    /// Stream of playback state changes.
    var playbackStateStream: AsyncStream<PlaybackState> { get }
}
