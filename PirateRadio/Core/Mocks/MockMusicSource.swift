import Foundation

/// A mock music source that simulates playback using wall-clock time.
/// Usable in the simulator (no Spotify SDK required) and in tests.
actor MockMusicSource: MusicSource {
    // MARK: - Playback State

    private var currentTrack: String?
    private var position: Duration = .zero
    private var isPlaying = false
    private var startTime: Date?

    // MARK: - Call Tracking (for tests)

    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var seekCallCount = 0
    private(set) var lastPlayedTrackID: String?
    private(set) var lastPlayedPosition: Duration?
    private(set) var lastSeekPosition: Duration?

    // MARK: - Streams

    let playbackStateStream: AsyncStream<PlaybackState>
    private let continuation: AsyncStream<PlaybackState>.Continuation

    init() {
        let (stream, cont) = AsyncStream.makeStream(of: PlaybackState.self, bufferingPolicy: .bufferingNewest(1))
        self.playbackStateStream = stream
        self.continuation = cont
    }

    // MARK: - MusicSource

    func play(trackID: String, at position: Duration) async throws {
        playCallCount += 1
        lastPlayedTrackID = trackID
        lastPlayedPosition = position
        currentTrack = trackID
        self.position = position
        isPlaying = true
        startTime = Date()

        #if DEBUG
        print("[MockMusic] play(\(trackID), at: \(position.seconds)s)")
        #endif

        continuation.yield(PlaybackState(
            trackID: trackID,
            isPlaying: true,
            positionSeconds: position.seconds,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000)
        ))
    }

    func pause() async throws {
        pauseCallCount += 1
        if isPlaying, let start = startTime {
            position = position + .seconds(Date().timeIntervalSince(start))
        }
        isPlaying = false
        startTime = nil

        #if DEBUG
        print("[MockMusic] pause() at \(position.seconds)s")
        #endif

        continuation.yield(PlaybackState(
            trackID: currentTrack,
            isPlaying: false,
            positionSeconds: position.seconds,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000)
        ))
    }

    func seek(to position: Duration) async throws {
        seekCallCount += 1
        lastSeekPosition = position
        self.position = position
        if isPlaying {
            startTime = Date()
        }

        #if DEBUG
        print("[MockMusic] seek(to: \(position.seconds)s)")
        #endif
    }

    func currentPosition() async throws -> Duration {
        guard isPlaying, let start = startTime else { return position }
        return position + .seconds(Date().timeIntervalSince(start))
    }

    // MARK: - Test Helpers

    func reset() {
        currentTrack = nil
        position = .zero
        isPlaying = false
        startTime = nil
        playCallCount = 0
        pauseCallCount = 0
        seekCallCount = 0
        lastPlayedTrackID = nil
        lastPlayedPosition = nil
        lastSeekPosition = nil
    }
}

// Duration.seconds helper (matches SyncEngine's private extension)
private extension Duration {
    var seconds: Double {
        let (seconds, attoseconds) = self.components
        return Double(seconds) + Double(attoseconds) / 1e18
    }

    static func seconds(_ value: Double) -> Duration {
        .nanoseconds(Int64(value * 1e9))
    }
}
