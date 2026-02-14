import Foundation
import SpotifyiOS
import os

private let logger = Logger(subsystem: "com.pirateradio", category: "SpotifyPlayer")

/// State machine wrapper around the SpotifyiOS App Remote SDK.
///
/// The Spotify SDK has unpredictable callback timing (50ms-2s+).
/// This wrapper serializes all SDK calls through a single state machine
/// to prevent overlapping operations and measure playback latency.
///
/// States: IDLE → PREPARING → WAITING_FOR_CALLBACK → PLAYING → IDLE
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

    /// The SPTAppRemote instance from SpotifyAuthManager.
    /// nonisolated(unsafe) because SPTAppRemote is thread-safe internally
    /// but not marked Sendable (Obj-C class).
    nonisolated(unsafe) private let appRemote: SPTAppRemote

    /// Average measured latency from play() call to actual playback start.
    /// Used by the sync engine to calibrate coordinated playback timing.
    var averagePlayLatency: TimeInterval {
        guard !latencyMeasurements.isEmpty else { return 0.3 } // default estimate
        return latencyMeasurements.suffix(5).reduce(0, +) / Double(min(latencyMeasurements.count, 5))
    }

    init(appRemote: SPTAppRemote) {
        let (stream, continuation) = AsyncStream.makeStream(of: PlaybackState.self, bufferingPolicy: .bufferingNewest(1))
        self.playbackStateStream = stream
        self.playbackContinuation = continuation
        self.appRemote = appRemote

        // Subscribe to player state changes once connected
        Task { await self.subscribeToPlayerState() }
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
        appRemote.playerAPI?.pause { _, error in
            if let error {
                logger.error("Pause failed: \(error.localizedDescription)")
            }
        }
        state = .idle
        playbackContinuation.yield(PlaybackState(
            trackID: currentTrackID,
            isPlaying: false,
            positionSeconds: 0,
            timestamp: UInt64(Date.now.timeIntervalSince1970 * 1000)
        ))
    }

    func seek(to position: Duration) async throws {
        let positionMs = Int(position.components.seconds * 1000 + position.components.attoseconds / 1_000_000_000_000_000)
        appRemote.playerAPI?.seek(toPosition: positionMs) { _, error in
            if let error {
                logger.error("Seek failed: \(error.localizedDescription)")
            }
        }
    }

    func currentPosition() async throws -> Duration {
        try await withCheckedThrowingContinuation { continuation in
            appRemote.playerAPI?.getPlayerState { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let playerState = result as? SPTAppRemotePlayerState {
                    let ms = playerState.playbackPosition
                    continuation.resume(returning: .milliseconds(ms))
                } else {
                    continuation.resume(returning: .zero)
                }
            }
        }
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
        logger.warning("Playback callback timed out for track: \(trackID)")
        state = .idle
        processPending()
    }

    /// Called when player state changes from Spotify. Updates internal state.
    func handlePlayerStateChange(_ playerState: SPTAppRemotePlayerState) {
        let trackURI = playerState.track.uri
        // Extract track ID from URI like "spotify:track:abc123"
        let trackID = trackURI.components(separatedBy: ":").last ?? trackURI

        if case .waitingForCallback(let expected, _) = state, expected == trackID {
            didStartPlayback(trackID: trackID)
        }

        playbackContinuation.yield(PlaybackState(
            trackID: trackID,
            isPlaying: !playerState.isPaused,
            positionSeconds: Double(playerState.playbackPosition) / 1000.0,
            timestamp: UInt64(Date.now.timeIntervalSince1970 * 1000)
        ))
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

        let uri = "spotify:track:\(trackID)"
        let positionMs = Int(position.components.seconds * 1000 + position.components.attoseconds / 1_000_000_000_000_000)

        appRemote.playerAPI?.play(uri) { [positionMs] _, error in
            if let error {
                logger.error("Play failed: \(error.localizedDescription)")
            } else if positionMs > 0 {
                self.appRemote.playerAPI?.seek(toPosition: positionMs) { _, error in
                    if let error {
                        logger.error("Seek after play failed: \(error.localizedDescription)")
                    }
                }
            }
        }

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

    private func subscribeToPlayerState() {
        // Wait briefly for connection to establish
        Task {
            try? await Task.sleep(for: .seconds(1))
            guard appRemote.isConnected else {
                logger.info("App Remote not connected, skipping player state subscription")
                return
            }
            appRemote.playerAPI?.subscribe(toPlayerState: { _, error in
                if let error {
                    logger.error("Failed to subscribe to player state: \(error.localizedDescription)")
                } else {
                    logger.notice("Subscribed to Spotify player state changes")
                }
            })
        }
    }

    private enum PendingCommand {
        case play(trackID: String, position: Duration)
    }
}
