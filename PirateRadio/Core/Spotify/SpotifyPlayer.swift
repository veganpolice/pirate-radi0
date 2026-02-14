import Foundation

/// State machine wrapper around the SpotifyiOS App Remote SDK.
///
/// The Spotify SDK has unpredictable callback timing (50ms-2s+).
/// This wrapper serializes all SDK calls through a single state machine
/// to prevent overlapping operations and measure playback latency.
///
/// States: IDLE → PREPARING → WAITING_FOR_CALLBACK → PLAYING → IDLE
///
/// Note: In a real build, this would import SpotifyiOS and use SPTAppRemote.
/// For now, this implements the protocol with the state machine structure
/// ready for SDK integration.
actor SpotifyPlayer: MusicSource {
    // MARK: - State Machine

    private enum State: Equatable {
        case idle
        case preparing(String) // trackID
        case waitingForCallback(String, deadline: Date)
        case playing(String)
    }

    private var state: State = .idle
    private var pendingCommand: PendingCommand?
    private var latencyMeasurements: [TimeInterval] = []
    private let callbackTimeout: TimeInterval = 3.0

    private let playbackContinuation: AsyncStream<PlaybackState>.Continuation
    let playbackStateStream: AsyncStream<PlaybackState>

    /// Average measured latency from play() call to actual playback start.
    /// Used by the sync engine to calibrate coordinated playback timing.
    var averagePlayLatency: TimeInterval {
        guard !latencyMeasurements.isEmpty else { return 0.3 } // default estimate
        return latencyMeasurements.suffix(5).reduce(0, +) / Double(min(latencyMeasurements.count, 5))
    }

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: PlaybackState.self, bufferingPolicy: .bufferingNewest(1))
        self.playbackStateStream = stream
        self.playbackContinuation = continuation
    }

    // MARK: - MusicSource Protocol

    func play(trackID: String, at position: Duration) async throws {
        switch state {
        case .idle, .playing:
            try await beginPlayback(trackID: trackID, position: position)
        case .preparing, .waitingForCallback:
            // Queue this command; only keep the latest pending
            pendingCommand = .play(trackID: trackID, position: position)
        }
    }

    func pause() async throws {
        // TODO: Call spotifyAppRemote.playerAPI?.pause()
        state = .idle
        playbackContinuation.yield(PlaybackState(
            trackID: currentTrackID,
            isPlaying: false,
            positionSeconds: 0,
            timestamp: UInt64(Date.now.timeIntervalSince1970 * 1000)
        ))
    }

    func seek(to position: Duration) async throws {
        // TODO: Call spotifyAppRemote.playerAPI?.seek(toPosition: Int(position.seconds * 1000))
    }

    func currentPosition() async throws -> Duration {
        // TODO: Query from spotifyAppRemote.playerAPI?.getPlayerState
        return .zero
    }

    // MARK: - SDK Callback (called when Spotify confirms playback started)

    /// Call this from the SPTAppRemotePlayerStateDelegate callback.
    func didStartPlayback(trackID: String) {
        guard case .waitingForCallback(let expectedTrack, let deadline) = state,
              expectedTrack == trackID else {
            return
        }

        // Measure latency
        let latency = Date.now.timeIntervalSince(deadline.addingTimeInterval(callbackTimeout))
        if latency > 0 {
            latencyMeasurements.append(callbackTimeout + latency)
        }

        state = .playing(trackID)
        playbackContinuation.yield(PlaybackState(
            trackID: trackID,
            isPlaying: true,
            positionSeconds: 0,
            timestamp: UInt64(Date.now.timeIntervalSince1970 * 1000)
        ))

        processPending()
    }

    /// Call this when the callback timeout fires.
    func callbackTimedOut(trackID: String) {
        guard case .waitingForCallback(let expected, _) = state, expected == trackID else {
            return
        }
        state = .idle
        processPending()
    }

    // MARK: - Private

    private var currentTrackID: String? {
        switch state {
        case .idle: return nil
        case .preparing(let id), .waitingForCallback(let id, _), .playing(let id): return id
        }
    }

    private func beginPlayback(trackID: String, position: Duration) async throws {
        state = .preparing(trackID)

        // TODO: Replace with actual Spotify SDK call:
        // spotifyAppRemote.playerAPI?.play("spotify:track:\(trackID)")
        // spotifyAppRemote.playerAPI?.seek(toPosition: Int(position.seconds * 1000))

        let deadline = Date.now.addingTimeInterval(callbackTimeout)
        state = .waitingForCallback(trackID, deadline: deadline)

        // Schedule timeout watchdog
        Task {
            try? await Task.sleep(for: .seconds(callbackTimeout))
            callbackTimedOut(trackID: trackID)
        }
    }

    private func processPending() {
        guard let command = pendingCommand else { return }
        pendingCommand = nil

        Task {
            switch command {
            case .play(let trackID, let position):
                try? await beginPlayback(trackID: trackID, position: position)
            }
        }
    }

    private enum PendingCommand {
        case play(trackID: String, position: Duration)
    }
}
