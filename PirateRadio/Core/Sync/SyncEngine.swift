import Foundation

/// The sync engine coordinates playback across devices using NTP-anchored timing.
///
/// In the public station model, all playback is server-driven via stateSync messages.
/// Clients only send: skip, addToQueue. The server handles queue advancement and
/// broadcasts stateSync with the current track and position.
actor SyncEngine {
    // MARK: - Dependencies

    private let musicSource: any MusicSource
    private let transport: any SessionTransport
    private let clock: any ClockProvider

    // MARK: - State

    private var currentEpoch: UInt64 = 0
    private var lastProcessedSeq: UInt64 = 0

    // Tasks (stored for cancellation)
    private var listeningTask: Task<Void, Never>?
    private var monitoringTask: Task<Void, Never>?
    private var driftCheckTask: Task<Void, Never>?
    private var lastCorrectionTime: UInt64 = 0
    private let correctionCooldownMs: UInt64 = 500

    // Current playback anchor
    private var currentAnchor: NTPAnchoredPosition?

    // Session store callback
    var onSessionUpdate: ((SessionUpdate) -> Void)?

    enum SessionUpdate {
        case trackChanged(Track?)
        case playbackStateChanged(isPlaying: Bool, positionMs: Int)
        case queueUpdated([Track])
        case memberJoined(UserID, String)
        case memberLeft(UserID)
        case connectionStateChanged(ConnectionState)
        case syncStatus(SyncStatus)
        case stateSynced(SessionSnapshot)
    }

    enum SyncStatus: Sendable {
        case synced
        case drifting(ms: Int)
        case correcting
        case lost
    }

    // MARK: - Init

    init(musicSource: any MusicSource, transport: any SessionTransport, clock: any ClockProvider) {
        self.musicSource = musicSource
        self.transport = transport
        self.clock = clock
    }

    // MARK: - Lifecycle

    func start(sessionID: SessionID, token: String) async throws {
        if !clock.isSynced {
            await clock.resync()
        }

        try await transport.connect(to: sessionID, token: token)

        startListening()
        startConnectionMonitoring()
    }

    func stop() async {
        listeningTask?.cancel()
        monitoringTask?.cancel()
        driftCheckTask?.cancel()
        listeningTask = nil
        monitoringTask = nil
        driftCheckTask = nil
        await transport.disconnect()
        try? await musicSource.pause()
    }

    // MARK: - Actions (available to all users)

    func sendAddToQueue(track: Track) async {
        let nonce = UUID().uuidString
        let msg = SyncMessage(
            id: UUID(),
            type: .addToQueue(track: track, nonce: nonce),
            sequenceNumber: 0,
            epoch: currentEpoch,
            timestamp: clock.now()
        )
        try? await transport.send(msg)
    }

    func sendSkip() async {
        let msg = SyncMessage(
            id: UUID(),
            type: .skip,
            sequenceNumber: 0,
            epoch: currentEpoch,
            timestamp: clock.now()
        )
        try? await transport.send(msg)
    }

    // MARK: - Message Processing

    private func startListening() {
        listeningTask?.cancel()
        listeningTask = Task {
            for await message in transport.incomingMessages {
                await processMessage(message)
            }
        }
    }

    private func processMessage(_ message: SyncMessage) async {
        // stateSync is a full snapshot — always process regardless of sequence/epoch
        if case .stateSync(let snapshot) = message.type {
            await handleStateSync(snapshot)
            onSessionUpdate?(.stateSynced(snapshot))
            return
        }

        // Epoch validation: ignore messages from old epochs
        if message.epoch < currentEpoch {
            return
        }
        // If new epoch, reset
        if message.epoch > currentEpoch {
            currentEpoch = message.epoch
            lastProcessedSeq = 0
        }

        // Sequence validation: ignore already-processed messages
        guard message.sequenceNumber > lastProcessedSeq else { return }
        lastProcessedSeq = message.sequenceNumber

        switch message.type {
        case .skip:
            // Server handles skip and sends stateSync
            break

        case .addToQueue:
            // Server handles and broadcasts queueUpdate
            break

        case .stateSync:
            break // handled above

        case .queueUpdate(let tracks):
            onSessionUpdate?(.queueUpdated(tracks))

        case .memberJoined(let userID, let displayName):
            onSessionUpdate?(.memberJoined(userID, displayName))

        case .memberLeft(let userID):
            onSessionUpdate?(.memberLeft(userID))
        }
    }

    // MARK: - State Sync (server-driven playback)

    private func handleStateSync(_ snapshot: SessionSnapshot) async {
        currentEpoch = snapshot.epoch
        lastProcessedSeq = snapshot.sequenceNumber

        guard let trackID = snapshot.trackID else {
            // Station is idle — stop playback
            driftCheckTask?.cancel()
            try? await musicSource.pause()
            currentAnchor = nil
            onSessionUpdate?(.playbackStateChanged(isPlaying: false, positionMs: 0))
            return
        }

        let now = clock.now()
        let currentPositionSec = snapshot.positionAtAnchor +
            (Double(now - snapshot.ntpAnchor) / 1000.0) * snapshot.playbackRate

        if snapshot.playbackRate > 0 {
            try? await musicSource.play(
                trackID: trackID,
                at: .seconds(currentPositionSec)
            )
            startDriftChecking()
            onSessionUpdate?(.playbackStateChanged(isPlaying: true, positionMs: Int(currentPositionSec * 1000)))
        } else {
            driftCheckTask?.cancel()
            try? await musicSource.pause()
            onSessionUpdate?(.playbackStateChanged(isPlaying: false, positionMs: 0))
        }

        currentAnchor = NTPAnchoredPosition(
            trackID: trackID,
            positionAtAnchor: snapshot.positionAtAnchor,
            ntpAnchor: snapshot.ntpAnchor,
            playbackRate: snapshot.playbackRate
        )
    }

    // MARK: - Catch-Up Playback

    /// Retries playback from the current anchor after Spotify becomes available.
    func retryCatchUpPlayback() async {
        guard let anchor = currentAnchor, anchor.playbackRate > 0 else { return }
        let now = clock.now()
        let currentPositionSec = anchor.positionAt(ntpTime: now)
        try? await musicSource.play(trackID: anchor.trackID, at: .seconds(currentPositionSec))
        startDriftChecking()
    }

    // MARK: - Drift Correction

    private func startDriftChecking() {
        driftCheckTask?.cancel()
        driftCheckTask = Task {
            var checkInterval: Duration = .seconds(5)
            var checksCount = 0

            while !Task.isCancelled {
                try? await Task.sleep(for: checkInterval)
                guard !Task.isCancelled else { break }

                await checkAndCorrectDrift()

                checksCount += 1
                if checksCount >= 12 {
                    checkInterval = .seconds(15)
                }
            }
        }
    }

    private func checkAndCorrectDrift() async {
        guard let anchor = currentAnchor else { return }

        let now = clock.now()
        guard now - lastCorrectionTime > correctionCooldownMs else { return }

        let expectedPositionMs = anchor.positionAt(ntpTime: now) * 1000
        guard let actualPosition = try? await musicSource.currentPosition() else { return }
        let actualPositionMs = actualPosition.seconds * 1000

        let driftMs = abs(expectedPositionMs - actualPositionMs)

        if driftMs < 50 {
            onSessionUpdate?(.syncStatus(.synced))
        } else if driftMs < 500 {
            onSessionUpdate?(.syncStatus(.drifting(ms: Int(driftMs))))
            lastCorrectionTime = now
        } else {
            onSessionUpdate?(.syncStatus(.correcting))
            let targetPosition = Duration.milliseconds(Int(expectedPositionMs))
            try? await musicSource.seek(to: targetPosition)
            lastCorrectionTime = now
        }
    }

    // MARK: - Connection Monitoring

    private func startConnectionMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = Task {
            for await state in transport.connectionState {
                onSessionUpdate?(.connectionStateChanged(state))

                switch state {
                case .resyncing:
                    break
                case .failed:
                    driftCheckTask?.cancel()
                    try? await musicSource.pause()
                default:
                    break
                }
            }
        }
    }
}

// MARK: - Duration helpers

private extension Duration {
    var seconds: Double {
        let (seconds, attoseconds) = self.components
        return Double(seconds) + Double(attoseconds) / 1e18
    }

    static func seconds(_ value: Double) -> Duration {
        .nanoseconds(Int64(value * 1e9))
    }
}
