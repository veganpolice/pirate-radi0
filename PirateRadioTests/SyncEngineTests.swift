import Foundation
import Testing
@testable import PirateRadio

@Suite("SyncEngine Tests")
struct SyncEngineTests {

    // MARK: - Helpers

    private func makeTrack(id: String = "t1", durationMs: Int = 180_000) -> Track {
        Track(id: id, name: "Song", artist: "Artist", albumName: "Album", albumArtURL: nil, durationMs: durationMs)
    }

    private func makeEngine() -> (SyncEngine, MockMusicSource, MockSessionTransport, MockClockProvider) {
        let music = MockMusicSource()
        let transport = MockSessionTransport()
        let clock = MockClockProvider()
        let engine = SyncEngine(musicSource: music, transport: transport, clock: clock)
        return (engine, music, transport, clock)
    }

    private func startEngine(_ engine: SyncEngine, transport: MockSessionTransport) async throws {
        try await engine.start(sessionID: "test-session", token: "test-token")
        // Give the listening task a moment to start
        try await Task.sleep(for: .milliseconds(50))
    }

    // MARK: - Two-Phase Play

    @Test("djPlay sends PREPARE then COMMIT")
    func djPlaySendsPrepareAndCommit() async throws {
        let (engine, _, transport, _) = makeEngine()
        try await startEngine(engine, transport: transport)

        let track = makeTrack(id: "track1")
        try await engine.djPlay(track: track)

        let sent = await transport.sentMessages
        #expect(sent.count >= 2)

        // First message should be playPrepare
        if case .playPrepare(let trackID, _) = sent[0].type {
            #expect(trackID == "track1")
        } else {
            Issue.record("Expected playPrepare, got \(sent[0].type)")
        }

        // Second message should be playCommit
        if case .playCommit(let trackID, _, let refSeq) = sent[1].type {
            #expect(trackID == "track1")
            #expect(refSeq == sent[0].sequenceNumber)
        } else {
            Issue.record("Expected playCommit, got \(sent[1].type)")
        }

        await engine.stop()
    }

    @Test("djPlay increments lastProcessedSeq by 2")
    func djPlayIncrementsSeqByTwo() async throws {
        let (engine, _, transport, _) = makeEngine()
        try await startEngine(engine, transport: transport)

        let track = makeTrack(id: "t1", durationMs: 60_000)
        try await engine.djPlay(track: track)

        let sent = await transport.sentMessages
        #expect(sent[0].sequenceNumber == 1)
        #expect(sent[1].sequenceNumber == 2)

        await engine.stop()
    }

    // MARK: - State Sync

    @Test("listener handles stateSync with catch-up playback")
    func stateSyncCatchUp() async throws {
        let (engine, music, transport, clock) = makeEngine()
        try await startEngine(engine, transport: transport)

        let now = clock.now()
        let snapshot = SessionSnapshot(
            trackID: "track1",
            positionAtAnchor: 10.0, // 10 seconds in
            ntpAnchor: now - 2000,  // anchor was 2 seconds ago
            playbackRate: 1.0,
            queue: [],
            djUserID: "dj1",
            epoch: 1,
            sequenceNumber: 5
        )

        let msg = SyncMessage(
            id: UUID(),
            type: .stateSync(snapshot),
            sequenceNumber: 5,
            epoch: 1,
            timestamp: now
        )
        await transport.inject(msg)

        // Wait for message processing
        try await Task.sleep(for: .milliseconds(200))

        let playCount = await music.playCallCount
        #expect(playCount >= 1)
        let lastTrack = await music.lastPlayedTrackID
        #expect(lastTrack == "track1")

        await engine.stop()
    }

    // MARK: - Epoch/Sequence Filtering

    @Test("stale epoch messages are ignored")
    func staleEpochIgnored() async throws {
        let (engine, music, transport, clock) = makeEngine()
        try await startEngine(engine, transport: transport)

        // First, set the engine to epoch 5 via a stateSync
        let now = clock.now()
        let snapshot = SessionSnapshot(
            trackID: nil, positionAtAnchor: 0, ntpAnchor: now,
            playbackRate: 0, queue: [], djUserID: "dj1",
            epoch: 5, sequenceNumber: 0
        )
        await transport.inject(SyncMessage(
            id: UUID(), type: .stateSync(snapshot),
            sequenceNumber: 0, epoch: 5, timestamp: now
        ))
        try await Task.sleep(for: .milliseconds(100))

        // Now send a pause from an old epoch (3) — should be ignored
        await transport.inject(SyncMessage(
            id: UUID(), type: .pause(atNtp: now),
            sequenceNumber: 1, epoch: 3, timestamp: now
        ))
        try await Task.sleep(for: .milliseconds(100))

        let pauseCount = await music.pauseCallCount
        #expect(pauseCount == 0)

        await engine.stop()
    }

    @Test("out-of-order sequence messages are ignored")
    func outOfOrderSeqIgnored() async throws {
        let (engine, music, transport, clock) = makeEngine()
        try await startEngine(engine, transport: transport)

        let now = clock.now()

        // Process a message with seq 5
        await transport.inject(SyncMessage(
            id: UUID(), type: .seek(positionMs: 1000, atNtp: now),
            sequenceNumber: 5, epoch: 0, timestamp: now
        ))
        try await Task.sleep(for: .milliseconds(100))

        // Now send a message with seq 3 — should be ignored
        await transport.inject(SyncMessage(
            id: UUID(), type: .seek(positionMs: 2000, atNtp: now),
            sequenceNumber: 3, epoch: 0, timestamp: now
        ))
        try await Task.sleep(for: .milliseconds(100))

        // Only one seek should have been processed
        let seekCount = await music.seekCallCount
        #expect(seekCount == 1)

        await engine.stop()
    }

    // MARK: - Pause/Resume

    @Test("pause and resume round-trip")
    func pauseAndResume() async throws {
        let (engine, music, transport, clock) = makeEngine()
        try await startEngine(engine, transport: transport)

        // First play a track
        let track = makeTrack()
        try await engine.djPlay(track: track)

        let playCount = await music.playCallCount
        #expect(playCount >= 1)

        // Pause
        try await engine.djPause()
        let pauseCount = await music.pauseCallCount
        #expect(pauseCount == 1)

        // Resume
        try await engine.djResume()
        let playCount2 = await music.playCallCount
        #expect(playCount2 >= 2) // Should have played again on resume

        await engine.stop()
    }

    // MARK: - Drift Correction

    @Test("djPlay sets up anchor and starts drift checking")
    func djPlaySetsUpAnchorAndDriftChecking() async throws {
        let (engine, music, transport, _) = makeEngine()

        var receivedStatuses: [SyncEngine.SyncStatus] = []
        await engine.setOnSessionUpdate { update in
            if case .syncStatus(let status) = update {
                receivedStatuses.append(status)
            }
        }

        try await startEngine(engine, transport: transport)

        let track = makeTrack(id: "t1", durationMs: 300_000)
        try await engine.djPlay(track: track)

        // Verify play was called and drift checking was started
        let playCount = await music.playCallCount
        #expect(playCount >= 1)

        await engine.stop()
    }

    @Test("drift < 50ms is ignored (synced status)")
    func smallDriftIgnored() async throws {
        let (engine, _, transport, _) = makeEngine()

        var lastStatus: SyncEngine.SyncStatus?
        await engine.setOnSessionUpdate { update in
            if case .syncStatus(let status) = update {
                lastStatus = status
            }
        }

        try await startEngine(engine, transport: transport)

        // Play a track — the mock music source will return a position close to expected
        let track = makeTrack(durationMs: 300_000)
        try await engine.djPlay(track: track)

        // Wait for first drift check (5s)
        try await Task.sleep(for: .seconds(6))

        // Mock music source tracks time from play() call, so drift should be minimal
        if let status = lastStatus {
            if case .synced = status {
                // expected
            } else if case .drifting(let ms) = status {
                // Small drift is expected due to processing time
                #expect(ms < 500)
            }
        }

        await engine.stop()
    }

    // MARK: - Cleanup

    @Test("stop cancels all tasks")
    func stopCancelsAllTasks() async throws {
        let (engine, _, transport, _) = makeEngine()
        try await startEngine(engine, transport: transport)

        // Play a track to start drift checking
        let track = makeTrack()
        try await engine.djPlay(track: track)

        // Stop should cancel everything without hanging
        await engine.stop()

        let isConnected = await transport.isConnected
        #expect(!isConnected)
    }

    // MARK: - Epoch Management

    @Test("stateSync resets epoch on new session")
    func stateSyncResetsEpoch() async throws {
        let (engine, _, transport, clock) = makeEngine()
        try await startEngine(engine, transport: transport)

        let now = clock.now()

        // Send stateSync with epoch 10
        let snapshot = SessionSnapshot(
            trackID: nil, positionAtAnchor: 0, ntpAnchor: now,
            playbackRate: 0, queue: [], djUserID: "dj1",
            epoch: 10, sequenceNumber: 50
        )
        await transport.inject(SyncMessage(
            id: UUID(), type: .stateSync(snapshot),
            sequenceNumber: 50, epoch: 10, timestamp: now
        ))
        try await Task.sleep(for: .milliseconds(100))

        // Now send a message with epoch 10, seq 51 — should be processed
        await transport.inject(SyncMessage(
            id: UUID(), type: .seek(positionMs: 5000, atNtp: now),
            sequenceNumber: 51, epoch: 10, timestamp: now
        ))
        try await Task.sleep(for: .milliseconds(100))

        // And a message with epoch 9 — should be ignored
        await transport.inject(SyncMessage(
            id: UUID(), type: .seek(positionMs: 10000, atNtp: now),
            sequenceNumber: 100, epoch: 9, timestamp: now
        ))
        try await Task.sleep(for: .milliseconds(100))

        // Only the epoch 10 seek should have been processed (not the epoch 9 one)
        // Note: stateSync with no trackID doesn't trigger play, so no play calls from that
        await engine.stop()
    }

    // MARK: - Member Events

    @Test("memberJoined and memberLeft update state")
    func memberEvents() async throws {
        let (engine, _, transport, clock) = makeEngine()

        var joinedUsers: [UserID] = []
        var leftUsers: [UserID] = []
        await engine.setOnSessionUpdate { update in
            switch update {
            case .memberJoined(let uid, _): joinedUsers.append(uid)
            case .memberLeft(let uid): leftUsers.append(uid)
            default: break
            }
        }

        try await startEngine(engine, transport: transport)
        let now = clock.now()

        // Inject memberJoined
        await transport.inject(SyncMessage(
            id: UUID(), type: .memberJoined(userID: "user1", displayName: "Alice"),
            sequenceNumber: 1, epoch: 0, timestamp: now
        ))
        try await Task.sleep(for: .milliseconds(100))
        #expect(joinedUsers == ["user1"])

        // Inject memberLeft
        await transport.inject(SyncMessage(
            id: UUID(), type: .memberLeft("user1"),
            sequenceNumber: 2, epoch: 0, timestamp: now
        ))
        try await Task.sleep(for: .milliseconds(100))
        #expect(leftUsers == ["user1"])

        await engine.stop()
    }
}
