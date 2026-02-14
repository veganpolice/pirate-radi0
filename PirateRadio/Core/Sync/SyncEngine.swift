import Foundation

/// The sync engine coordinates playback across devices using NTP-anchored timing.
///
/// Architecture:
/// - Two-phase coordinated play: PREPARE (pre-warm track) → COMMIT (play at NTP time)
/// - Three-tier drift correction: IGNORE (<50ms) → RATE ADJUST (50-500ms) → HARD SEEK (>500ms)
/// - Per-device latency calibration from the first 3 play commands
/// - Monotonic sequence numbers + epochs prevent stale/duplicate execution
actor SyncEngine {
    // MARK: - Dependencies

    private let musicSource: any MusicSource
    private let transport: any SessionTransport
    private let clock: any ClockProvider

    // MARK: - State

    private var currentEpoch: UInt64 = 0
    private var lastProcessedSeq: UInt64 = 0
    private var preparedTrackID: String?

    // Drift correction
    private var driftCheckTask: Task<Void, Never>?
    private var lastCorrectionTime: UInt64 = 0
    private let correctionCooldownMs: UInt64 = 500

    // Latency calibration
    private var playLatencySamples: [TimeInterval] = []
    private var calibratedLatency: TimeInterval { averageLatency ?? 0.3 }

    private var averageLatency: TimeInterval? {
        guard !playLatencySamples.isEmpty else { return nil }
        let recent = playLatencySamples.suffix(5)
        return recent.reduce(0, +) / Double(recent.count)
    }

    // Current playback anchor
    private var currentAnchor: NTPAnchoredPosition?

    // Session store callback
    var onSessionUpdate: ((SessionUpdate) -> Void)?

    enum SessionUpdate {
        case trackChanged(Track?)
        case playbackStateChanged(isPlaying: Bool, positionMs: Int)
        case queueUpdated([String])
        case memberJoined(UserID, String)
        case memberLeft(UserID)
        case connectionStateChanged(ConnectionState)
        case syncStatus(SyncStatus)
        case anchorUpdated(NTPAnchoredPosition, clockOffsetMs: Int64)
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
        driftCheckTask?.cancel()
        driftCheckTask = nil
        await transport.disconnect()
        try? await musicSource.pause()
    }

    // MARK: - DJ Actions (only called by the DJ device)

    func djPlay(track: Track, positionMs: Int = 0) async throws {
        let now = clock.now()
        let leadTime: UInt64 = 1500 // ms
        let commitTime = now + leadTime

        // Phase 1: PREPARE — tell everyone to pre-warm the track
        let prepareMsg = SyncMessage(
            id: UUID(),
            type: .playPrepare(trackID: track.id, prepareDeadline: commitTime),
            sequenceNumber: lastProcessedSeq + 1,
            epoch: currentEpoch,
            timestamp: now
        )
        try await transport.send(prepareMsg)

        // Pre-warm locally
        preparedTrackID = track.id

        // Wait for lead time
        try await Task.sleep(for: .milliseconds(Int(leadTime)))

        // Phase 2: COMMIT — play at exact NTP time
        let commitNtp = clock.now() + 200 // tiny buffer for message transit
        let commitMsg = SyncMessage(
            id: UUID(),
            type: .playCommit(trackID: track.id, startAtNtp: commitNtp, refSeq: prepareMsg.sequenceNumber),
            sequenceNumber: lastProcessedSeq + 2,
            epoch: currentEpoch,
            timestamp: clock.now()
        )
        try await transport.send(commitMsg)

        // Execute locally
        await executePlayCommit(trackID: track.id, startAtNtp: commitNtp, positionMs: positionMs)

        lastProcessedSeq += 2
        startDriftChecking()
    }

    func djPause() async throws {
        let now = clock.now()
        let msg = SyncMessage(
            id: UUID(),
            type: .pause(atNtp: now + 100),
            sequenceNumber: lastProcessedSeq + 1,
            epoch: currentEpoch,
            timestamp: now
        )
        try await transport.send(msg)
        lastProcessedSeq += 1

        try await musicSource.pause()
        driftCheckTask?.cancel()
        onSessionUpdate?(.playbackStateChanged(isPlaying: false, positionMs: 0))
    }

    func djResume() async throws {
        let now = clock.now()
        let resumeAt = now + 1500
        let msg = SyncMessage(
            id: UUID(),
            type: .resume(atNtp: resumeAt),
            sequenceNumber: lastProcessedSeq + 1,
            epoch: currentEpoch,
            timestamp: now
        )
        try await transport.send(msg)
        lastProcessedSeq += 1

        await schedulePlayAt(ntpTime: resumeAt)
        startDriftChecking()
    }

    func djSeek(to positionMs: Int) async throws {
        let now = clock.now()
        let msg = SyncMessage(
            id: UUID(),
            type: .seek(positionMs: positionMs, atNtp: now + 200),
            sequenceNumber: lastProcessedSeq + 1,
            epoch: currentEpoch,
            timestamp: now
        )
        try await transport.send(msg)
        lastProcessedSeq += 1

        try await musicSource.seek(to: .milliseconds(positionMs))
    }

    // MARK: - Message Processing

    private func startListening() {
        Task {
            for await message in transport.incomingMessages {
                await processMessage(message)
            }
        }
    }

    private func processMessage(_ message: SyncMessage) async {
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
        case .playPrepare(let trackID, _):
            // Pre-warm: just record that we should be ready for this track
            preparedTrackID = trackID

        case .playCommit(let trackID, let startAtNtp, _):
            await executePlayCommit(trackID: trackID, startAtNtp: startAtNtp, positionMs: 0)
            startDriftChecking()

        case .pause:
            try? await musicSource.pause()
            driftCheckTask?.cancel()
            onSessionUpdate?(.playbackStateChanged(isPlaying: false, positionMs: 0))

        case .resume(let atNtp):
            await schedulePlayAt(ntpTime: atNtp)
            startDriftChecking()

        case .seek(let positionMs, _):
            try? await musicSource.seek(to: .milliseconds(positionMs))

        case .skip:
            // Handled by the queue system
            break

        case .driftReport:
            // DJ receives drift reports from listeners — monitoring only
            break

        case .stateSync(let snapshot):
            await handleStateSync(snapshot)

        case .queueUpdate(let trackIDs):
            onSessionUpdate?(.queueUpdated(trackIDs))

        case .memberJoined(let userID):
            onSessionUpdate?(.memberJoined(userID, ""))

        case .memberLeft(let userID):
            onSessionUpdate?(.memberLeft(userID))
        }
    }

    // MARK: - Playback Execution

    private func executePlayCommit(trackID: String, startAtNtp: UInt64, positionMs: Int) async {
        let now = clock.now()
        let waitMs = Int64(startAtNtp) - Int64(now) - Int64(calibratedLatency * 1000)

        if waitMs > 0 {
            try? await Task.sleep(for: .milliseconds(waitMs))
        }

        // Measure latency
        let startTime = ProcessInfo.processInfo.systemUptime

        let position = Duration.milliseconds(positionMs)
        try? await musicSource.play(trackID: trackID, at: position)

        let elapsed = ProcessInfo.processInfo.systemUptime - startTime
        if playLatencySamples.count < 10 {
            playLatencySamples.append(elapsed)
        }

        let anchor = NTPAnchoredPosition(
            trackID: trackID,
            positionAtAnchor: Double(positionMs) / 1000.0,
            ntpAnchor: startAtNtp,
            playbackRate: 1.0
        )
        currentAnchor = anchor

        let offsetMs = Int64(clock.estimatedOffset.seconds * 1000)
        onSessionUpdate?(.anchorUpdated(anchor, clockOffsetMs: offsetMs))
        onSessionUpdate?(.playbackStateChanged(isPlaying: true, positionMs: positionMs))
    }

    private func schedulePlayAt(ntpTime: UInt64) async {
        let now = clock.now()
        let waitMs = Int64(ntpTime) - Int64(now) - Int64(calibratedLatency * 1000)

        if waitMs > 0 {
            try? await Task.sleep(for: .milliseconds(waitMs))
        }

        guard let anchor = currentAnchor else { return }
        let position = Duration.seconds(anchor.positionAt(ntpTime: ntpTime))
        try? await musicSource.play(trackID: anchor.trackID, at: position)
    }

    // MARK: - Drift Correction

    private func startDriftChecking() {
        driftCheckTask?.cancel()
        driftCheckTask = Task {
            // Fast checks for the first minute (every 5s), then slow (every 15s)
            var checkInterval: Duration = .seconds(5)
            var checksCount = 0

            while !Task.isCancelled {
                try? await Task.sleep(for: checkInterval)
                guard !Task.isCancelled else { break }

                await checkAndCorrectDrift()

                checksCount += 1
                if checksCount >= 12 { // After ~60s of fast checks
                    checkInterval = .seconds(15)
                }
            }
        }
    }

    private func checkAndCorrectDrift() async {
        guard let anchor = currentAnchor else { return }

        let now = clock.now()

        // Cooldown: don't correct within 500ms of the last correction
        guard now - lastCorrectionTime > correctionCooldownMs else { return }

        let expectedPositionMs = anchor.positionAt(ntpTime: now) * 1000
        guard let actualPosition = try? await musicSource.currentPosition() else { return }
        let actualPositionMs = actualPosition.seconds * 1000

        let driftMs = abs(expectedPositionMs - actualPositionMs)

        if driftMs < 50 {
            // Tier 1: IGNORE — within acceptable range
            onSessionUpdate?(.syncStatus(.synced))
        } else if driftMs < 500 {
            // Tier 2: RATE ADJUST — inaudible speed change
            // If behind, speed up slightly; if ahead, slow down
            // Note: playback rate adjustment requires SpotifyiOS SDK support.
            // For now, this is a placeholder — the actual rate adjustment
            // will be done through the SDK when integrated.
            onSessionUpdate?(.syncStatus(.drifting(ms: Int(driftMs))))
            lastCorrectionTime = now
        } else {
            // Tier 3: HARD SEEK — audible but necessary
            onSessionUpdate?(.syncStatus(.correcting))
            let targetPosition = Duration.milliseconds(Int(expectedPositionMs))
            try? await musicSource.seek(to: targetPosition)
            lastCorrectionTime = now
        }

        // Report drift to DJ
        let driftReport = SyncMessage(
            id: UUID(),
            type: .driftReport(
                trackID: anchor.trackID,
                positionMs: Int(actualPositionMs),
                ntpTimestamp: now
            ),
            sequenceNumber: 0, // drift reports don't need sequencing
            epoch: currentEpoch,
            timestamp: now
        )
        try? await transport.send(driftReport)
    }

    // MARK: - State Sync (reconnection / join-mid-song)

    private func handleStateSync(_ snapshot: SessionSnapshot) async {
        currentEpoch = snapshot.epoch
        lastProcessedSeq = snapshot.sequenceNumber

        guard let trackID = snapshot.trackID else { return }

        let now = clock.now()
        let currentPositionSec = snapshot.positionAtAnchor +
            (Double(now - snapshot.ntpAnchor) / 1000.0) * snapshot.playbackRate

        if snapshot.playbackRate > 0 {
            try? await musicSource.play(
                trackID: trackID,
                at: .seconds(currentPositionSec)
            )
            startDriftChecking()
        }

        let anchor = NTPAnchoredPosition(
            trackID: trackID,
            positionAtAnchor: snapshot.positionAtAnchor,
            ntpAnchor: snapshot.ntpAnchor,
            playbackRate: snapshot.playbackRate
        )
        currentAnchor = anchor

        let offsetMs = Int64(clock.estimatedOffset.seconds * 1000)
        onSessionUpdate?(.anchorUpdated(anchor, clockOffsetMs: offsetMs))
    }

    // MARK: - Connection Monitoring

    private func startConnectionMonitoring() {
        Task {
            for await state in transport.connectionState {
                onSessionUpdate?(.connectionStateChanged(state))

                switch state {
                case .resyncing:
                    // After reconnection, the server sends a stateSync message
                    // which will be processed in processMessage
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
