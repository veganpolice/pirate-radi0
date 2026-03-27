import Foundation
import SpotifyiOS

/// State machine wrapper around the SpotifyiOS App Remote SDK.
///
/// The Spotify SDK has unpredictable callback timing (50ms-2s+).
/// This wrapper serializes all SDK calls through a single state machine
/// to prevent overlapping operations and measure playback latency.
///
/// States: IDLE → PREPARING → WAITING_FOR_CALLBACK → PLAYING → IDLE
///
/// Runs on @MainActor because SPTAppRemote delivers delegate callbacks on the main thread.
@MainActor
final class SpotifyPlayer: NSObject, MusicSource {
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
    private var commandStartTime: Date?

    // MARK: - SPTAppRemote

    private let appRemote: SPTAppRemote
    private var playerStateContinuation: CheckedContinuation<SPTAppRemotePlayerState, Error>?

    // MARK: - Streams

    private let playbackContinuation: AsyncStream<PlaybackState>.Continuation
    let playbackStateStream: AsyncStream<PlaybackState>

    /// Average measured latency from play() call to actual playback start.
    /// Used by the sync engine to calibrate coordinated playback timing.
    var averagePlayLatency: TimeInterval {
        guard !latencyMeasurements.isEmpty else { return 0.3 } // default estimate
        return latencyMeasurements.suffix(5).reduce(0, +) / Double(min(latencyMeasurements.count, 5))
    }

    // MARK: - Init

    init(accessToken: String) {
        let configuration = SPTConfiguration(
            clientID: SpotifyAuthManager.clientID,
            redirectURL: URL(string: SpotifyAuthManager.redirectURI)!
        )
        self.appRemote = SPTAppRemote(configuration: configuration, logLevel: .debug)
        appRemote.connectionParameters.accessToken = accessToken

        let (stream, continuation) = AsyncStream.makeStream(of: PlaybackState.self, bufferingPolicy: .bufferingNewest(1))
        self.playbackStateStream = stream
        self.playbackContinuation = continuation

        super.init()

        appRemote.delegate = self
    }

    // MARK: - Connection

    /// Connect to the Spotify app. Call after init and when the app becomes active.
    /// On first connection, this opens the Spotify app for authorization.
    func connect() {
        guard !appRemote.isConnected else { return }
        // Try direct connect first (works if previously authorized)
        appRemote.connect()
    }

    /// Open the Spotify app for authorization. Call this if connect() fails
    /// or on first launch to establish the App Remote connection.
    func authorizeAndConnect() {
        guard !appRemote.isConnected else { return }
        // This opens Spotify app, which triggers a redirect back with auth params
        appRemote.authorizeAndPlayURI("", asRadio: false, additionalScopes: nil)
    }

    /// Disconnect from the Spotify app. Call when the app resigns active.
    func disconnect() {
        if appRemote.isConnected {
            appRemote.disconnect()
        }
    }

    /// Handle the authorization URL returned by Spotify app.
    /// Returns true if this URL was handled by SPTAppRemote.
    func handleURL(_ url: URL) -> Bool {
        let params = appRemote.authorizationParameters(from: url)
        if params != nil {
            // Got auth params from Spotify — now connect
            if let accessToken = params?[SPTAppRemoteAccessTokenKey] {
                appRemote.connectionParameters.accessToken = accessToken
            }
            appRemote.connect()
            return true
        }
        return false
    }

    // MARK: - MusicSource Protocol

    nonisolated func play(trackID: String, at position: Duration) async throws {
        try await MainActor.run {
            try self.beginPlaybackSync(trackID: trackID, position: position)
        }
    }

    nonisolated func pause() async throws {
        await MainActor.run {
            guard self.appRemote.isConnected else { return }
            self.appRemote.playerAPI?.pause(nil)
            self.state = .idle
            self.playbackContinuation.yield(PlaybackState(
                trackID: self.currentTrackID,
                isPlaying: false,
                positionSeconds: 0,
                timestamp: UInt64(Date.now.timeIntervalSince1970 * 1000)
            ))
        }
    }

    nonisolated func seek(to position: Duration) async throws {
        await MainActor.run {
            guard self.appRemote.isConnected else { return }
            let posMs = Int(position.components.seconds * 1000 + position.components.attoseconds / 1_000_000_000_000_000)
            self.appRemote.playerAPI?.seek(toPosition: posMs, callback: nil)
        }
    }

    nonisolated func currentPosition() async throws -> Duration {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                guard self.appRemote.isConnected else {
                    continuation.resume(throwing: PirateRadioError.notConnected)
                    return
                }
                self.appRemote.playerAPI?.getPlayerState { result, error in
                    if let error {
                        continuation.resume(throwing: PirateRadioError.playbackFailed(underlying: error))
                        return
                    }
                    guard let playerState = result as? SPTAppRemotePlayerState else {
                        continuation.resume(returning: .zero)
                        return
                    }
                    let positionMs = playerState.playbackPosition
                    continuation.resume(returning: .milliseconds(positionMs))
                }
            }
        }
    }

    // MARK: - Private

    private var currentTrackID: String? {
        switch state {
        case .idle: return nil
        case .preparing(let id), .waitingForCallback(let id, _), .playing(let id): return id
        }
    }

    private func beginPlaybackSync(trackID: String, position: Duration) throws {
        guard appRemote.isConnected else {
            // Try to connect; the pending command will be queued
            print("[SpotifyPlayer] Not connected, attempting to connect for playback")
            authorizeAndConnect()
            pendingCommand = .play(trackID: trackID, position: position)
            return
        }

        switch state {
        case .idle, .playing:
            state = .preparing(trackID)
            commandStartTime = Date.now

            let uri = "spotify:track:\(trackID)"
            appRemote.playerAPI?.play(uri, callback: { [weak self] _, error in
                guard let self else { return }
                Task { @MainActor in
                    if let error {
                        print("[SpotifyPlayer] play error: \(error)")
                        self.state = .idle
                        self.processPending()
                        return
                    }

                    // Seek to position if non-zero
                    let posMs = Int(position.components.seconds * 1000 + position.components.attoseconds / 1_000_000_000_000_000)
                    if posMs > 0 {
                        self.appRemote.playerAPI?.seek(toPosition: posMs, callback: nil)
                    }

                    let deadline = Date.now.addingTimeInterval(self.callbackTimeout)
                    self.state = .waitingForCallback(trackID, deadline: deadline)

                    // Timeout watchdog
                    Task {
                        try? await Task.sleep(for: .seconds(self.callbackTimeout))
                        self.callbackTimedOut(trackID: trackID)
                    }
                }
            })

        case .preparing, .waitingForCallback:
            pendingCommand = .play(trackID: trackID, position: position)
        }
    }

    /// Called from the player state delegate when Spotify confirms playback.
    private func didStartPlayback(trackID: String) {
        guard case .waitingForCallback(let expectedTrack, _) = state,
              expectedTrack == trackID else {
            return
        }

        // Measure latency
        if let start = commandStartTime {
            let latency = Date.now.timeIntervalSince(start)
            latencyMeasurements.append(latency)
            if latencyMeasurements.count > 10 {
                latencyMeasurements.removeFirst()
            }
        }
        commandStartTime = nil

        state = .playing(trackID)
        playbackContinuation.yield(PlaybackState(
            trackID: trackID,
            isPlaying: true,
            positionSeconds: 0,
            timestamp: UInt64(Date.now.timeIntervalSince1970 * 1000)
        ))

        processPending()
    }

    private func callbackTimedOut(trackID: String) {
        guard case .waitingForCallback(let expected, _) = state, expected == trackID else {
            return
        }
        print("[SpotifyPlayer] Callback timed out for \(trackID)")
        commandStartTime = nil
        state = .idle
        processPending()
    }

    private func processPending() {
        guard let command = pendingCommand else { return }
        pendingCommand = nil

        switch command {
        case .play(let trackID, let position):
            try? beginPlaybackSync(trackID: trackID, position: position)
        }
    }

    private enum PendingCommand {
        case play(trackID: String, position: Duration)
    }
}

// MARK: - SPTAppRemoteDelegate

extension SpotifyPlayer: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in
            print("[SpotifyPlayer] Connected to Spotify app")
            appRemote.playerAPI?.delegate = self
            // Subscribe to player state changes
            appRemote.playerAPI?.subscribe(toPlayerState: { _, error in
                if let error {
                    print("[SpotifyPlayer] Failed to subscribe to player state: \(error)")
                }
            })
            // Process any queued play command
            self.processPending()
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        Task { @MainActor in
            print("[SpotifyPlayer] Connection failed: \(error?.localizedDescription ?? "unknown")")
            // If direct connect fails, try opening Spotify for authorization
            self.authorizeAndConnect()
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        Task { @MainActor in
            print("[SpotifyPlayer] Disconnected: \(error?.localizedDescription ?? "none")")
        }
    }
}

// MARK: - SPTAppRemotePlayerStateDelegate

extension SpotifyPlayer: SPTAppRemotePlayerStateDelegate {
    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        Task { @MainActor in
            let trackURI = playerState.track.uri
            // Extract track ID from URI: "spotify:track:XXXX" → "XXXX"
            let trackID = trackURI.components(separatedBy: ":").last ?? trackURI

            if !playerState.isPaused {
                self.didStartPlayback(trackID: trackID)
            }

            self.playbackContinuation.yield(PlaybackState(
                trackID: trackID,
                isPlaying: !playerState.isPaused,
                positionSeconds: Double(playerState.playbackPosition) / 1000.0,
                timestamp: UInt64(Date.now.timeIntervalSince1970 * 1000)
            ))
        }
    }
}
