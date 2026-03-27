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
    private var hasAuthorized = false // only open Spotify app once

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

    /// Open the Spotify app for authorization with a specific track URI.
    /// Only called once — subsequent reconnections use connect() which doesn't app-switch.
    func authorizeAndConnect(playURI: String = "") {
        guard !appRemote.isConnected else { return }
        hasAuthorized = true
        // This opens Spotify app, which triggers a redirect back with auth params.
        // Passing the track URI makes Spotify start the right song immediately.
        appRemote.authorizeAndPlayURI(playURI, asRadio: false, additionalScopes: nil)
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
            // Queue the command to replay once connected
            pendingCommand = .play(trackID: trackID, position: position)

            if hasAuthorized {
                // Already authorized once — just reconnect (no app switch)
                print("[SpotifyPlayer] Not connected, reconnecting (no app switch)")
                appRemote.connect()
            } else {
                // First time — open Spotify with the actual track URI so it starts right
                print("[SpotifyPlayer] Not connected, authorizing with track \(trackID)")
                authorizeAndConnect(playURI: "spotify:track:\(trackID)")
            }
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

            // Check what Spotify is actually playing before replaying pending command.
            // If authorizeAndConnect already started the right track, skip the redundant play.
            if case .play(let trackID, _) = self.pendingCommand {
                appRemote.playerAPI?.getPlayerState { [weak self] result, _ in
                    guard let self else { return }
                    Task { @MainActor in
                        if let playerState = result as? SPTAppRemotePlayerState {
                            let playingID = playerState.track.uri.components(separatedBy: ":").last ?? ""
                            if playingID == trackID && !playerState.isPaused {
                                // Already playing the right track — just update state
                                print("[SpotifyPlayer] Track \(trackID) already playing, skipping redundant play")
                                self.pendingCommand = nil
                                self.state = .playing(trackID)
                                self.playbackContinuation.yield(PlaybackState(
                                    trackID: trackID,
                                    isPlaying: true,
                                    positionSeconds: Double(playerState.playbackPosition) / 1000.0,
                                    timestamp: UInt64(Date.now.timeIntervalSince1970 * 1000)
                                ))
                                return
                            }
                        }
                        // Different track or not playing — process the pending command
                        self.processPending()
                    }
                }
            } else {
                self.processPending()
            }
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        Task { @MainActor in
            print("[SpotifyPlayer] Connection failed: \(error?.localizedDescription ?? "unknown")")
            if !self.hasAuthorized {
                // Only open Spotify app if we haven't authorized yet.
                // Pass the pending track URI if we have one queued.
                let uri: String
                if case .play(let trackID, _) = self.pendingCommand {
                    uri = "spotify:track:\(trackID)"
                } else {
                    uri = ""
                }
                self.authorizeAndConnect(playURI: uri)
            }
            // If already authorized, don't re-open Spotify — the user will
            // come back to the app and applicationDidBecomeActive will reconnect.
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
