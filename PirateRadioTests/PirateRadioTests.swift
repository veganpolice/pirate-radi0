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
            positionMs: 10_000,
            ntpTimestamp: 1_000_000
        )
        // 500ms later, position should be 10500ms
        let position = anchor.positionAt(ntpTime: 1_000_500)
        #expect(position == 10_500)
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
