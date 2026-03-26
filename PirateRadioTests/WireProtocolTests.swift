import Foundation
import Testing
@testable import PirateRadio

// MARK: - Server → Client Decoding Tests

@Suite("Wire Protocol: Server → Client")
struct ServerToClientTests {

    private func decode(_ json: String) -> SyncMessage? {
        guard let data = json.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(ServerEnvelope.self, from: data) else {
            return nil
        }
        return envelope.toSyncMessage()
    }

    @Test("playPrepare decodes correctly")
    func playPrepare() {
        let json = """
        {"type":"playPrepare","data":{"trackId":"abc123","track":{"id":"abc123"}},"epoch":1,"seq":3,"timestamp":1700000000000}
        """
        let msg = decode(json)
        #expect(msg != nil)
        #expect(msg?.epoch == 1)
        #expect(msg?.sequenceNumber == 3)
        if case .playPrepare(let trackID, _) = msg?.type {
            #expect(trackID == "abc123")
        } else {
            Issue.record("Expected .playPrepare, got \(String(describing: msg?.type))")
        }
    }

    @Test("playCommit decodes correctly")
    func playCommit() {
        let json = """
        {"type":"playCommit","data":{"ntpTimestamp":1700000001500,"positionMs":0},"epoch":1,"seq":4,"timestamp":1700000001000}
        """
        let msg = decode(json)
        #expect(msg != nil)
        if case .playCommit(_, let startAtNtp, _) = msg?.type {
            #expect(startAtNtp == 1700000001500)
        } else {
            Issue.record("Expected .playCommit")
        }
    }

    @Test("pause decodes correctly")
    func pause() {
        let json = """
        {"type":"pause","data":{"positionMs":45000,"ntpTimestamp":1700000002000},"epoch":1,"seq":5,"timestamp":1700000002000}
        """
        let msg = decode(json)
        #expect(msg != nil)
        if case .pause(let atNtp) = msg?.type {
            #expect(atNtp == 1700000002000)
        } else {
            Issue.record("Expected .pause")
        }
    }

    @Test("resume decodes with executionTime")
    func resume() {
        let json = """
        {"type":"resume","data":{"positionMs":45000,"ntpTimestamp":1700000003000,"executionTime":1700000004500},"epoch":1,"seq":6,"timestamp":1700000003000}
        """
        let msg = decode(json)
        #expect(msg != nil)
        if case .resume(let atNtp) = msg?.type {
            #expect(atNtp == 1700000004500)
        } else {
            Issue.record("Expected .resume")
        }
    }

    @Test("seek decodes correctly")
    func seek() {
        let json = """
        {"type":"seek","data":{"positionMs":90000},"epoch":1,"seq":7,"timestamp":1700000005000}
        """
        let msg = decode(json)
        #expect(msg != nil)
        if case .seek(let positionMs, _) = msg?.type {
            #expect(positionMs == 90000)
        } else {
            Issue.record("Expected .seek")
        }
    }

    @Test("memberJoined decodes correctly")
    func memberJoined() {
        let json = """
        {"type":"memberJoined","data":{"userId":"user-42","displayName":"Alice"},"epoch":1,"seq":8,"timestamp":1700000006000}
        """
        let msg = decode(json)
        #expect(msg != nil)
        if case .memberJoined(let userID) = msg?.type {
            #expect(userID == "user-42")
        } else {
            Issue.record("Expected .memberJoined")
        }
    }

    @Test("memberLeft decodes correctly")
    func memberLeft() {
        let json = """
        {"type":"memberLeft","data":{"userId":"user-42"},"epoch":1,"seq":9,"timestamp":1700000007000}
        """
        let msg = decode(json)
        #expect(msg != nil)
        if case .memberLeft(let userID) = msg?.type {
            #expect(userID == "user-42")
        } else {
            Issue.record("Expected .memberLeft")
        }
    }

    @Test("queueUpdate decodes track IDs from queue objects")
    func queueUpdate() {
        let json = """
        {"type":"queueUpdate","data":{"queue":[{"id":"t1","name":"Song 1"},{"id":"t2","name":"Song 2"}]},"epoch":1,"seq":10,"timestamp":1700000008000}
        """
        let msg = decode(json)
        #expect(msg != nil)
        if case .queueUpdate(let trackIDs) = msg?.type {
            #expect(trackIDs == ["t1", "t2"])
        } else {
            Issue.record("Expected .queueUpdate")
        }
    }

    @Test("stateSync decodes full snapshot")
    func stateSync() {
        let json = """
        {"type":"stateSync","data":{"id":"session-1","joinCode":"1073","creatorId":"dj-1","djUserId":"dj-1","members":[{"userId":"dj-1","displayName":"DJ"}],"epoch":2,"sequence":15,"currentTrack":{"id":"track-abc"},"isPlaying":true,"positionMs":45000,"positionTimestamp":1700000000000,"queue":[{"id":"q1"},{"id":"q2"}]}}
        """
        let msg = decode(json)
        #expect(msg != nil)
        if case .stateSync(let snapshot) = msg?.type {
            #expect(snapshot.trackID == "track-abc")
            #expect(snapshot.positionAtAnchor == 45.0) // 45000ms / 1000
            #expect(snapshot.ntpAnchor == 1700000000000)
            #expect(snapshot.playbackRate == 1.0) // isPlaying = true
            #expect(snapshot.djUserID == "dj-1")
            #expect(snapshot.epoch == 2)
            #expect(snapshot.sequenceNumber == 15)
            #expect(snapshot.queue == ["q1", "q2"])
        } else {
            Issue.record("Expected .stateSync")
        }
    }

    @Test("stateSync with no current track")
    func stateSyncNoTrack() {
        let json = """
        {"type":"stateSync","data":{"id":"s1","joinCode":"1234","creatorId":"u1","djUserId":"u1","members":[],"epoch":0,"sequence":0,"currentTrack":null,"isPlaying":false,"positionMs":0,"positionTimestamp":0,"queue":[]}}
        """
        let msg = decode(json)
        #expect(msg != nil)
        if case .stateSync(let snapshot) = msg?.type {
            #expect(snapshot.trackID == nil)
            #expect(snapshot.playbackRate == 0.0) // isPlaying = false
        } else {
            Issue.record("Expected .stateSync")
        }
    }

    @Test("unknown message type returns nil")
    func unknownType() {
        let json = """
        {"type":"futureFeature","data":{},"epoch":0,"seq":0,"timestamp":0}
        """
        let msg = decode(json)
        #expect(msg == nil)
    }

    @Test("pong message returns nil (handled separately)")
    func pongReturnsNil() {
        let json = """
        {"type":"pong","data":{"clientSendTime":100,"serverTime":200}}
        """
        let msg = decode(json)
        #expect(msg == nil)
    }

    @Test("driftReport decodes correctly")
    func driftReport() {
        let json = """
        {"type":"driftReport","data":{"trackId":"t1","positionMs":12345,"ntpTimestamp":3000000,"fromUserId":"user-5"},"timestamp":3000000}
        """
        let msg = decode(json)
        #expect(msg != nil)
        if case .driftReport(let trackID, let posMs, let ntp) = msg?.type {
            #expect(trackID == "t1")
            #expect(posMs == 12345)
            #expect(ntp == 3000000)
        } else {
            Issue.record("Expected .driftReport")
        }
    }
}

// MARK: - Client → Server Encoding Tests

@Suite("Wire Protocol: Client → Server")
struct ClientToServerTests {

    private func encode(_ message: SyncMessage) -> [String: Any]? {
        guard let data = try? message.toServerJSON(),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    @Test("playPrepare encodes to server format")
    func playPrepare() {
        let msg = SyncMessage(
            id: UUID(),
            type: .playPrepare(trackID: "track-1", prepareDeadline: 5000),
            sequenceNumber: 1, epoch: 0, timestamp: 1000
        )
        let json = encode(msg)
        #expect(json?["type"] as? String == "playPrepare")
        let dataObj = json?["data"] as? [String: Any]
        #expect(dataObj?["trackId"] as? String == "track-1")
    }

    @Test("playCommit encodes to server format")
    func playCommit() {
        let msg = SyncMessage(
            id: UUID(),
            type: .playCommit(trackID: "track-2", startAtNtp: 1700000001000, refSeq: 1),
            sequenceNumber: 2, epoch: 0, timestamp: 1000
        )
        let json = encode(msg)
        #expect(json?["type"] as? String == "playCommit")
        let dataObj = json?["data"] as? [String: Any]
        #expect(dataObj?["trackId"] as? String == "track-2")
        #expect(dataObj?["ntpTimestamp"] as? UInt64 == 1700000001000)
    }

    @Test("pause encodes to server format")
    func pause() {
        let msg = SyncMessage(
            id: UUID(),
            type: .pause(atNtp: 9999),
            sequenceNumber: 3, epoch: 0, timestamp: 1000
        )
        let json = encode(msg)
        #expect(json?["type"] as? String == "pause")
    }

    @Test("driftReport encodes to server format")
    func driftReport() {
        let msg = SyncMessage(
            id: UUID(),
            type: .driftReport(trackID: "t1", positionMs: 12345, ntpTimestamp: 3000000),
            sequenceNumber: 0, epoch: 0, timestamp: 3000000
        )
        let json = encode(msg)
        #expect(json?["type"] as? String == "driftReport")
        let dataObj = json?["data"] as? [String: Any]
        #expect(dataObj?["trackId"] as? String == "t1")
        #expect(dataObj?["positionMs"] as? Int == 12345)
    }

    @Test("resume encodes with executionTime")
    func resume() {
        let msg = SyncMessage(
            id: UUID(),
            type: .resume(atNtp: 4500),
            sequenceNumber: 4, epoch: 0, timestamp: 1000
        )
        let json = encode(msg)
        #expect(json?["type"] as? String == "resume")
        let dataObj = json?["data"] as? [String: Any]
        #expect(dataObj?["executionTime"] as? UInt64 == 4500)
    }

    @Test("seek encodes to server format")
    func seek() {
        let msg = SyncMessage(
            id: UUID(),
            type: .seek(positionMs: 90000, atNtp: 2000000),
            sequenceNumber: 5, epoch: 0, timestamp: 1000
        )
        let json = encode(msg)
        #expect(json?["type"] as? String == "seek")
        let dataObj = json?["data"] as? [String: Any]
        #expect(dataObj?["positionMs"] as? Int == 90000)
    }
}
