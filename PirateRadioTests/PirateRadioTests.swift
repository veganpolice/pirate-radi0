import Foundation
import Testing
@testable import PirateRadio

@Suite("PirateRadio Core Tests")
struct PirateRadioTests {

    @Test("Track duration formatting")
    func trackDurationFormatted() {
        let track = Track(
            id: "abc123",
            name: "Test Song",
            artist: "Test Artist",
            albumName: "Test Album",
            albumArtURL: nil,
            durationMs: 215_000 // 3:35
        )
        #expect(track.durationFormatted == "3:35")
    }

    @Test("Track duration formatting with leading zero seconds")
    func trackDurationFormattedLeadingZero() {
        let track = Track(
            id: "abc123",
            name: "Short",
            artist: "Artist",
            albumName: "Album",
            albumArtURL: nil,
            durationMs: 61_000 // 1:01
        )
        #expect(track.durationFormatted == "1:01")
    }

    @Test("Session join code is 4 characters")
    func sessionJoinCodeLength() {
        let session = Session(
            id: "session-1",
            joinCode: "ABCD",
            creatorID: "user-1",
            djUserID: "user-1",
            members: [],
            queue: [],
            currentTrack: nil,
            isPlaying: false,
            epoch: 0
        )
        #expect(session.joinCode.count == 4)
    }

    @Test("NTPAnchoredPosition computes offset correctly")
    func ntpAnchoredPosition() {
        let anchor = NTPAnchoredPosition(
            trackID: "track-1",
            positionAtAnchor: 10.0,
            ntpAnchor: 1_000_000,
            playbackRate: 1.0
        )
        // 500ms later, position should be 10.5s
        let position = anchor.positionAt(ntpTime: 1_000_500)
        #expect(position == 10.5)
    }

    @Test("PirateRadioError descriptions are non-empty")
    func errorDescriptions() {
        let errors: [PirateRadioError] = [
            .notAuthenticated,
            .tokenExpired,
            .spotifyNotPremium,
            .sessionNotFound,
            .sessionFull,
            .playbackFailed(underlying: NSError(domain: "test", code: 0)),
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}

// MARK: - SyncCommand Codable Tests

@Suite("SyncCommand Codable Round-Trip")
struct SyncCommandCodableTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func makeCommand(type: SyncCommand.CommandType) -> SyncCommand {
        SyncCommand(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!,
            type: type,
            executionTime: 1_700_000_000_000,
            issuedBy: "user-1",
            sequenceNumber: 42,
            epoch: 3
        )
    }

    private func roundTrip(_ command: SyncCommand) throws -> SyncCommand {
        let data = try encoder.encode(command)
        return try decoder.decode(SyncCommand.self, from: data)
    }

    @Test("play command round-trips through JSON")
    func playCommandRoundTrip() throws {
        let original = makeCommand(type: .play(trackID: "spotify:track:abc", startPosition: 12.5))
        let decoded = try roundTrip(original)
        #expect(decoded.id == original.id)
        #expect(decoded.executionTime == original.executionTime)
        #expect(decoded.issuedBy == original.issuedBy)
        #expect(decoded.sequenceNumber == original.sequenceNumber)
        #expect(decoded.epoch == original.epoch)
        if case .play(let trackID, let startPosition) = decoded.type {
            #expect(trackID == "spotify:track:abc")
            #expect(startPosition == 12.5)
        } else {
            Issue.record("Expected .play, got \(decoded.type)")
        }
    }

    @Test("pause command round-trips through JSON")
    func pauseCommandRoundTrip() throws {
        let original = makeCommand(type: .pause)
        let decoded = try roundTrip(original)
        if case .pause = decoded.type {
            // pass
        } else {
            Issue.record("Expected .pause, got \(decoded.type)")
        }
    }

    @Test("resume command round-trips through JSON")
    func resumeCommandRoundTrip() throws {
        let original = makeCommand(type: .resume)
        let decoded = try roundTrip(original)
        if case .resume = decoded.type {
            // pass
        } else {
            Issue.record("Expected .resume, got \(decoded.type)")
        }
    }

    @Test("seek command round-trips through JSON")
    func seekCommandRoundTrip() throws {
        let original = makeCommand(type: .seek(to: 99.9))
        let decoded = try roundTrip(original)
        if case .seek(let to) = decoded.type {
            #expect(to == 99.9)
        } else {
            Issue.record("Expected .seek, got \(decoded.type)")
        }
    }

    @Test("skip command round-trips through JSON")
    func skipCommandRoundTrip() throws {
        let original = makeCommand(type: .skip)
        let decoded = try roundTrip(original)
        if case .skip = decoded.type {
            // pass
        } else {
            Issue.record("Expected .skip, got \(decoded.type)")
        }
    }

    @Test("addToQueue command round-trips through JSON")
    func addToQueueCommandRoundTrip() throws {
        let original = makeCommand(type: .addToQueue(trackID: "track-xyz", nonce: "nonce-1"))
        let decoded = try roundTrip(original)
        if case .addToQueue(let trackID, let nonce) = decoded.type {
            #expect(trackID == "track-xyz")
            #expect(nonce == "nonce-1")
        } else {
            Issue.record("Expected .addToQueue, got \(decoded.type)")
        }
    }

    @Test("removeFromQueue command round-trips through JSON")
    func removeFromQueueCommandRoundTrip() throws {
        let original = makeCommand(type: .removeFromQueue(trackID: "track-remove"))
        let decoded = try roundTrip(original)
        if case .removeFromQueue(let trackID) = decoded.type {
            #expect(trackID == "track-remove")
        } else {
            Issue.record("Expected .removeFromQueue, got \(decoded.type)")
        }
    }
}

// MARK: - NTPAnchoredPosition Tests

@Suite("NTPAnchoredPosition")
struct NTPAnchoredPositionTests {

    @Test("positionAt returns anchor position when paused (rate 0.0)")
    func pausedPlaybackDoesNotAdvance() {
        let anchor = NTPAnchoredPosition(
            trackID: "track-1",
            positionAtAnchor: 30.0,
            ntpAnchor: 1_000_000,
            playbackRate: 0.0
        )
        // Even 10 seconds later, position should remain at the anchor
        let position = anchor.positionAt(ntpTime: 1_010_000)
        #expect(position == 30.0)
    }

    @Test("positionAt advances correctly at normal rate (1.0)")
    func normalPlaybackAdvances() {
        let anchor = NTPAnchoredPosition(
            trackID: "track-1",
            positionAtAnchor: 5.0,
            ntpAnchor: 1_000_000,
            playbackRate: 1.0
        )
        // 2 seconds later
        let position = anchor.positionAt(ntpTime: 1_002_000)
        #expect(position == 7.0)
    }

    @Test("positionAt handles large time gaps (30 minutes)")
    func largeTimeGap() {
        let anchor = NTPAnchoredPosition(
            trackID: "track-1",
            positionAtAnchor: 0.0,
            ntpAnchor: 1_000_000,
            playbackRate: 1.0
        )
        // 30 minutes = 1,800,000 ms later
        let position = anchor.positionAt(ntpTime: 2_800_000)
        #expect(position == 1800.0)
    }

    @Test("positionAt at exact anchor time returns anchor position")
    func zeroElapsedTime() {
        let anchor = NTPAnchoredPosition(
            trackID: "track-1",
            positionAtAnchor: 42.5,
            ntpAnchor: 5_000_000,
            playbackRate: 1.0
        )
        let position = anchor.positionAt(ntpTime: 5_000_000)
        #expect(position == 42.5)
    }

    @Test("positionAt does not go negative when anchor is at zero and time equals anchor")
    func positionDoesNotGoNegativeAtAnchor() {
        let anchor = NTPAnchoredPosition(
            trackID: "track-1",
            positionAtAnchor: 0.0,
            ntpAnchor: 1_000_000,
            playbackRate: 1.0
        )
        let position = anchor.positionAt(ntpTime: 1_000_000)
        #expect(position >= 0.0)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = NTPAnchoredPosition(
            trackID: "track-1",
            positionAtAnchor: 15.75,
            ntpAnchor: 9_999_999,
            playbackRate: 1.0
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NTPAnchoredPosition.self, from: data)
        #expect(decoded.trackID == original.trackID)
        #expect(decoded.positionAtAnchor == original.positionAtAnchor)
        #expect(decoded.ntpAnchor == original.ntpAnchor)
        #expect(decoded.playbackRate == original.playbackRate)
    }
}

// MARK: - PirateRadioError Tests

@Suite("PirateRadioError Descriptions")
struct PirateRadioErrorTests {

    @Test("All error cases have non-empty descriptions")
    func allErrorDescriptionsNonEmpty() {
        let errors: [PirateRadioError] = [
            .notAuthenticated,
            .spotifyNotInstalled,
            .spotifyNotLoggedIn,
            .spotifyNotPremium,
            .tokenExpired,
            .tokenRefreshFailed(underlying: NSError(domain: "test", code: 1)),
            .sessionNotFound,
            .sessionFull,
            .invalidJoinCode,
            .notAuthorized(action: "skip track"),
            .sessionCreationFailed(underlying: NSError(domain: "test", code: 2)),
            .notConnected,
            .clockSyncFailed,
            .driftUnrecoverable(offsetMs: 500),
            .transportDisconnected,
            .trackNotAvailable(trackID: "track-123"),
            .playbackFailed(underlying: NSError(domain: "test", code: 3)),
            .playbackTimeout,
        ]
        for error in errors {
            #expect(error.errorDescription != nil, "errorDescription should not be nil for \(error)")
            #expect(error.errorDescription?.isEmpty == false, "errorDescription should not be empty for \(error)")
        }
    }

    @Test("notAuthenticated description mentions sign in")
    func notAuthenticatedDescription() {
        let error = PirateRadioError.notAuthenticated
        #expect(error.errorDescription?.contains("sign in") == true)
    }

    @Test("notConnected description mentions connected")
    func notConnectedDescription() {
        let error = PirateRadioError.notConnected
        #expect(error.errorDescription?.localizedCaseInsensitiveContains("connected") == true)
    }

    @Test("sessionCreationFailed description mentions create")
    func sessionCreationFailedDescription() {
        let error = PirateRadioError.sessionCreationFailed(
            underlying: NSError(domain: "test", code: 0)
        )
        #expect(error.errorDescription?.localizedCaseInsensitiveContains("create") == true)
    }

    @Test("notAuthorized description includes the action")
    func notAuthorizedIncludesAction() {
        let error = PirateRadioError.notAuthorized(action: "change DJ")
        #expect(error.errorDescription?.contains("change DJ") == true)
    }

    @Test("trackNotAvailable description includes track ID")
    func trackNotAvailableIncludesTrackID() {
        let error = PirateRadioError.trackNotAvailable(trackID: "abc-xyz-123")
        #expect(error.errorDescription?.contains("abc-xyz-123") == true)
    }
}

// MARK: - SyncMessage Codable Tests

@Suite("SyncMessage Codable Round-Trip")
struct SyncMessageCodableTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func makeMessage(type: SyncMessage.SyncMessageType) -> SyncMessage {
        SyncMessage(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            type: type,
            sequenceNumber: 7,
            epoch: 1,
            timestamp: 1_700_000_000_000
        )
    }

    private func roundTrip(_ message: SyncMessage) throws -> SyncMessage {
        let data = try encoder.encode(message)
        return try decoder.decode(SyncMessage.self, from: data)
    }

    @Test("playPrepare round-trips through JSON")
    func playPrepareRoundTrip() throws {
        let original = makeMessage(type: .playPrepare(trackID: "track-1", prepareDeadline: 5_000))
        let decoded = try roundTrip(original)
        #expect(decoded.id == original.id)
        #expect(decoded.sequenceNumber == original.sequenceNumber)
        #expect(decoded.epoch == original.epoch)
        if case .playPrepare(let trackID, let deadline) = decoded.type {
            #expect(trackID == "track-1")
            #expect(deadline == 5_000)
        } else {
            Issue.record("Expected .playPrepare, got \(decoded.type)")
        }
    }

    @Test("playCommit round-trips through JSON")
    func playCommitRoundTrip() throws {
        let original = makeMessage(type: .playCommit(trackID: "track-2", startAtNtp: 1_700_000_001_000, refSeq: 6))
        let decoded = try roundTrip(original)
        if case .playCommit(let trackID, let startAt, let refSeq) = decoded.type {
            #expect(trackID == "track-2")
            #expect(startAt == 1_700_000_001_000)
            #expect(refSeq == 6)
        } else {
            Issue.record("Expected .playCommit, got \(decoded.type)")
        }
    }

    @Test("pause round-trips through JSON")
    func pauseRoundTrip() throws {
        let original = makeMessage(type: .pause(atNtp: 9_999))
        let decoded = try roundTrip(original)
        if case .pause(let atNtp) = decoded.type {
            #expect(atNtp == 9_999)
        } else {
            Issue.record("Expected .pause, got \(decoded.type)")
        }
    }

    @Test("resume round-trips through JSON")
    func resumeRoundTrip() throws {
        let original = makeMessage(type: .resume(atNtp: 10_001))
        let decoded = try roundTrip(original)
        if case .resume(let atNtp) = decoded.type {
            #expect(atNtp == 10_001)
        } else {
            Issue.record("Expected .resume, got \(decoded.type)")
        }
    }

    @Test("seek round-trips through JSON")
    func seekRoundTrip() throws {
        let original = makeMessage(type: .seek(positionMs: 45_000, atNtp: 2_000_000))
        let decoded = try roundTrip(original)
        if case .seek(let positionMs, let atNtp) = decoded.type {
            #expect(positionMs == 45_000)
            #expect(atNtp == 2_000_000)
        } else {
            Issue.record("Expected .seek, got \(decoded.type)")
        }
    }

    @Test("skip round-trips through JSON")
    func skipRoundTrip() throws {
        let original = makeMessage(type: .skip)
        let decoded = try roundTrip(original)
        if case .skip = decoded.type {
            // pass
        } else {
            Issue.record("Expected .skip, got \(decoded.type)")
        }
    }

    @Test("driftReport round-trips through JSON")
    func driftReportRoundTrip() throws {
        let original = makeMessage(type: .driftReport(trackID: "t-1", positionMs: 12_345, ntpTimestamp: 3_000_000))
        let decoded = try roundTrip(original)
        if case .driftReport(let trackID, let posMs, let ntp) = decoded.type {
            #expect(trackID == "t-1")
            #expect(posMs == 12_345)
            #expect(ntp == 3_000_000)
        } else {
            Issue.record("Expected .driftReport, got \(decoded.type)")
        }
    }

    @Test("stateSync round-trips through JSON")
    func stateSyncRoundTrip() throws {
        let snapshot = SessionSnapshot(
            trackID: "snap-track",
            positionAtAnchor: 22.5,
            ntpAnchor: 4_000_000,
            playbackRate: 1.0,
            queue: ["q1", "q2"],
            djUserID: "dj-user",
            epoch: 5,
            sequenceNumber: 100
        )
        let original = makeMessage(type: .stateSync(snapshot))
        let decoded = try roundTrip(original)
        if case .stateSync(let decodedSnapshot) = decoded.type {
            #expect(decodedSnapshot.trackID == "snap-track")
            #expect(decodedSnapshot.positionAtAnchor == 22.5)
            #expect(decodedSnapshot.ntpAnchor == 4_000_000)
            #expect(decodedSnapshot.playbackRate == 1.0)
            #expect(decodedSnapshot.queue == ["q1", "q2"])
            #expect(decodedSnapshot.djUserID == "dj-user")
            #expect(decodedSnapshot.epoch == 5)
            #expect(decodedSnapshot.sequenceNumber == 100)
        } else {
            Issue.record("Expected .stateSync, got \(decoded.type)")
        }
    }

    @Test("queueUpdate round-trips through JSON")
    func queueUpdateRoundTrip() throws {
        let original = makeMessage(type: .queueUpdate(["a", "b", "c"]))
        let decoded = try roundTrip(original)
        if case .queueUpdate(let trackIDs) = decoded.type {
            #expect(trackIDs == ["a", "b", "c"])
        } else {
            Issue.record("Expected .queueUpdate, got \(decoded.type)")
        }
    }

    @Test("memberJoined round-trips through JSON")
    func memberJoinedRoundTrip() throws {
        let original = makeMessage(type: .memberJoined(userID: "new-user", displayName: "New User"))
        let decoded = try roundTrip(original)
        if case .memberJoined(let userID, let displayName) = decoded.type {
            #expect(userID == "new-user")
            #expect(displayName == "New User")
        } else {
            Issue.record("Expected .memberJoined, got \(decoded.type)")
        }
    }

    @Test("memberLeft round-trips through JSON")
    func memberLeftRoundTrip() throws {
        let original = makeMessage(type: .memberLeft("gone-user"))
        let decoded = try roundTrip(original)
        if case .memberLeft(let userID) = decoded.type {
            #expect(userID == "gone-user")
        } else {
            Issue.record("Expected .memberLeft, got \(decoded.type)")
        }
    }
}

// MARK: - Track Edge Case Tests

@Suite("Track Duration Edge Cases")
struct TrackDurationEdgeCaseTests {

    private func makeTrack(durationMs: Int) -> Track {
        Track(
            id: "test",
            name: "Test",
            artist: "Artist",
            albumName: "Album",
            albumArtURL: nil,
            durationMs: durationMs
        )
    }

    @Test("0ms duration formats as 0:00")
    func zeroDuration() {
        let track = makeTrack(durationMs: 0)
        #expect(track.durationFormatted == "0:00")
    }

    @Test("999ms duration formats as 0:00 (sub-second truncation)")
    func subSecondDuration() {
        let track = makeTrack(durationMs: 999)
        #expect(track.durationFormatted == "0:00")
    }

    @Test("1000ms duration formats as 0:01")
    func exactlyOneSecond() {
        let track = makeTrack(durationMs: 1_000)
        #expect(track.durationFormatted == "0:01")
    }

    @Test("59 seconds formats as 0:59")
    func fiftyNineSeconds() {
        let track = makeTrack(durationMs: 59_000)
        #expect(track.durationFormatted == "0:59")
    }

    @Test("Exactly 1 hour formats as 60:00")
    func exactlyOneHour() {
        let track = makeTrack(durationMs: 3_600_000)
        #expect(track.durationFormatted == "60:00")
    }

    @Test("Over 1 hour formats correctly (1h 23m 45s = 83:45)")
    func overOneHour() {
        // 1h 23m 45s = 5025 seconds = 5_025_000 ms
        let track = makeTrack(durationMs: 5_025_000)
        #expect(track.durationFormatted == "83:45")
    }

    @Test("Very long track (3 hours) formats correctly")
    func threeHours() {
        // 3h = 10800 seconds = 10_800_000 ms => 180:00
        let track = makeTrack(durationMs: 10_800_000)
        #expect(track.durationFormatted == "180:00")
    }
}

// MARK: - Track Codable Tests

@Suite("Track Codable Round-Trip")
struct TrackCodableTests {

    @Test("Track round-trips through JSON with albumArtURL")
    func trackWithURLRoundTrip() throws {
        let original = Track(
            id: "6rqhFgbbKwnb9MLmUQDhG6",
            name: "Bohemian Rhapsody",
            artist: "Queen",
            albumName: "A Night at the Opera",
            albumArtURL: URL(string: "https://i.scdn.co/image/abc123"),
            durationMs: 354_000
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Track.self, from: data)
        #expect(decoded == original)
    }

    @Test("Track round-trips through JSON with nil albumArtURL")
    func trackWithNilURLRoundTrip() throws {
        let original = Track(
            id: "test-id",
            name: "Local Track",
            artist: "Unknown",
            albumName: "Unknown Album",
            albumArtURL: nil,
            durationMs: 180_000
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Track.self, from: data)
        #expect(decoded == original)
        #expect(decoded.albumArtURL == nil)
    }
}

// MARK: - Session Member Tests

@Suite("Session Member Manipulation")
struct SessionMemberTests {

    private func makeSession(members: [Session.Member] = []) -> Session {
        Session(
            id: "session-1",
            joinCode: "1234",
            creatorID: "creator",
            djUserID: "creator",
            members: members,
            queue: [],
            currentTrack: nil,
            isPlaying: false,
            epoch: 0
        )
    }

    private func makeMember(id: String, name: String, connected: Bool = true) -> Session.Member {
        Session.Member(id: id, displayName: name, isConnected: connected)
    }

    @Test("Session starts with empty members array")
    func emptyMembers() {
        let session = makeSession()
        #expect(session.members.isEmpty)
    }

    @Test("Adding a member increases count")
    func addMember() {
        var session = makeSession()
        session.members.append(makeMember(id: "user-1", name: "Alice"))
        #expect(session.members.count == 1)
        #expect(session.members[0].id == "user-1")
        #expect(session.members[0].displayName == "Alice")
    }

    @Test("Removing a member by ID")
    func removeMember() {
        var session = makeSession(members: [
            makeMember(id: "user-1", name: "Alice"),
            makeMember(id: "user-2", name: "Bob"),
            makeMember(id: "user-3", name: "Carol"),
        ])
        session.members.removeAll { $0.id == "user-2" }
        #expect(session.members.count == 2)
        #expect(session.members.contains { $0.id == "user-2" } == false)
    }

    @Test("Updating member connection status")
    func updateMemberConnectionStatus() {
        var session = makeSession(members: [
            makeMember(id: "user-1", name: "Alice", connected: true),
        ])
        #expect(session.members[0].isConnected == true)
        session.members[0].isConnected = false
        #expect(session.members[0].isConnected == false)
    }

    @Test("Session with multiple members preserves order")
    func memberOrder() {
        let session = makeSession(members: [
            makeMember(id: "user-a", name: "Alpha"),
            makeMember(id: "user-b", name: "Bravo"),
            makeMember(id: "user-c", name: "Charlie"),
        ])
        #expect(session.members[0].displayName == "Alpha")
        #expect(session.members[1].displayName == "Bravo")
        #expect(session.members[2].displayName == "Charlie")
    }

    @Test("Session queue manipulation")
    func queueManipulation() {
        var session = makeSession()
        let track1 = Track(id: "t1", name: "Song 1", artist: "A", albumName: "Al", albumArtURL: nil, durationMs: 200_000)
        let track2 = Track(id: "t2", name: "Song 2", artist: "B", albumName: "Al", albumArtURL: nil, durationMs: 300_000)
        session.queue.append(track1)
        session.queue.append(track2)
        #expect(session.queue.count == 2)
        #expect(session.queue[0].id == "t1")

        // Remove first from queue
        session.queue.removeFirst()
        #expect(session.queue.count == 1)
        #expect(session.queue[0].id == "t2")
    }

    @Test("Session Codable round-trip preserves all fields")
    func sessionCodableRoundTrip() throws {
        let track = Track(id: "t1", name: "Song", artist: "A", albumName: "Al", albumArtURL: nil, durationMs: 200_000)
        let original = Session(
            id: "session-99",
            joinCode: "9876",
            creatorID: "creator-1",
            djUserID: "dj-1",
            members: [
                makeMember(id: "m1", name: "Member 1"),
                makeMember(id: "m2", name: "Member 2", connected: false),
            ],
            queue: [track],
            currentTrack: track,
            isPlaying: true,
            epoch: 5
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Session.self, from: data)
        #expect(decoded == original)
        #expect(decoded.members.count == 2)
        #expect(decoded.queue.count == 1)
        #expect(decoded.currentTrack == track)
        #expect(decoded.isPlaying == true)
        #expect(decoded.epoch == 5)
    }
}
