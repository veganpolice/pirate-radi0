import Foundation

// MARK: - Server Wire Format

/// Decodes the flat JSON envelopes sent by the Node.js server.
///
/// Server format: `{"type": "playPrepare", "data": {...}, "epoch": 1, "seq": 2, "timestamp": 1234}`
/// Swift format:  `SyncMessage` with typed enum cases and named fields.
///
/// This struct bridges the two, handling field name differences (`trackId` vs `trackID`,
/// `seq` vs `sequenceNumber`) and structural differences (flat `data` object vs enum associated values).
struct ServerEnvelope: Sendable {
    let type: String
    let data: [String: JSONValue]
    let epoch: UInt64
    let seq: UInt64
    let timestamp: UInt64
}

extension ServerEnvelope: Decodable {
    enum CodingKeys: String, CodingKey {
        case type, data, epoch, seq, timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        data = try container.decodeIfPresent([String: JSONValue].self, forKey: .data) ?? [:]
        epoch = try container.decodeIfPresent(UInt64.self, forKey: .epoch) ?? 0
        seq = try container.decodeIfPresent(UInt64.self, forKey: .seq) ?? 0
        timestamp = try container.decodeIfPresent(UInt64.self, forKey: .timestamp) ?? 0
    }
}

// MARK: - ServerEnvelope → SyncMessage

extension ServerEnvelope {
    func toSyncMessage() -> SyncMessage? {
        let msgType: SyncMessage.SyncMessageType?

        switch type {
        case "playPrepare":
            guard let trackID = data["trackId"]?.stringValue ?? data["trackID"]?.stringValue else { return nil }
            let deadline = data["prepareDeadline"]?.uint64Value ?? 0
            msgType = .playPrepare(trackID: trackID, prepareDeadline: deadline)

        case "playCommit":
            guard let trackID = data["trackId"]?.stringValue ?? data["trackID"]?.stringValue else { return nil }
            let ntpTimestamp = data["ntpTimestamp"]?.uint64Value ?? timestamp
            let positionMs = data["positionMs"]?.intValue ?? 0
            // refSeq not sent by server; use seq - 1 as approximation
            msgType = .playCommit(trackID: trackID, startAtNtp: ntpTimestamp, refSeq: seq > 0 ? seq - 1 : 0)

        case "pause":
            let ntpTimestamp = data["ntpTimestamp"]?.uint64Value ?? timestamp
            msgType = .pause(atNtp: ntpTimestamp)

        case "resume":
            let ntpTimestamp = data["executionTime"]?.uint64Value ?? data["ntpTimestamp"]?.uint64Value ?? timestamp
            msgType = .resume(atNtp: ntpTimestamp)

        case "seek":
            let positionMs = data["positionMs"]?.intValue ?? 0
            let ntpTimestamp = data["ntpTimestamp"]?.uint64Value ?? timestamp
            msgType = .seek(positionMs: positionMs, atNtp: ntpTimestamp)

        case "queueUpdate":
            let queue = data["queue"]?.arrayValue ?? []
            msgType = .queueUpdate(parseTracks(from: queue))

        case "memberJoined":
            guard let userID = data["userId"]?.stringValue else { return nil }
            msgType = .memberJoined(userID)

        case "memberLeft":
            guard let userID = data["userId"]?.stringValue else { return nil }
            msgType = .memberLeft(userID)

        case "stateSync":
            guard let snapshot = serverSnapshotToSessionSnapshot() else { return nil }
            msgType = .stateSync(snapshot)

        case "pong":
            // Clock sync pong — not a SyncMessage type, handled separately
            return nil

        case "driftReport":
            guard let trackID = data["trackId"]?.stringValue ?? data["trackID"]?.stringValue else { return nil }
            let positionMs = data["positionMs"]?.intValue ?? 0
            let ntpTimestamp = data["ntpTimestamp"]?.uint64Value ?? timestamp
            msgType = .driftReport(trackID: trackID, positionMs: positionMs, ntpTimestamp: ntpTimestamp)

        default:
            return nil
        }

        guard let resolvedType = msgType else { return nil }

        return SyncMessage(
            id: UUID(),
            type: resolvedType,
            sequenceNumber: seq,
            epoch: epoch,
            timestamp: timestamp
        )
    }

    /// For `stateSync` messages, the server sends the full snapshot as the `data` field.
    /// This extracts it into a `SessionSnapshot`.
    private func serverSnapshotToSessionSnapshot() -> SessionSnapshot? {
        // The stateSync wraps the snapshot in `data`
        let src = data
        let trackID = src["currentTrack"]?.objectValue?["id"]?.stringValue
        let currentTrack: Track? = src["currentTrack"].flatMap { parseTrack(from: $0) }
        let positionMs = src["positionMs"]?.doubleValue ?? 0
        let positionTimestamp = src["positionTimestamp"]?.uint64Value ?? 0
        let sequenceNumber = src["sequence"]?.uint64Value ?? seq
        let snapshotEpoch = src["epoch"]?.uint64Value ?? epoch
        let djUserID = src["djUserId"]?.stringValue ?? ""
        let isPlaying = src["isPlaying"]?.boolValue ?? false

        let queueArray = src["queue"]?.arrayValue ?? []
        let queueTracks = parseTracks(from: queueArray)

        return SessionSnapshot(
            trackID: trackID,
            currentTrack: currentTrack,
            positionAtAnchor: positionMs / 1000.0,
            ntpAnchor: positionTimestamp,
            playbackRate: isPlaying ? 1.0 : 0.0,
            queue: queueTracks,
            djUserID: djUserID,
            epoch: snapshotEpoch,
            sequenceNumber: sequenceNumber
        )
    }
}

// MARK: - Track parsing from server JSON

private func parseTrack(from json: JSONValue) -> Track? {
    guard let obj = json.objectValue,
          let id = obj["id"]?.stringValue else { return nil }
    let name = obj["name"]?.stringValue ?? ""
    let artist = obj["artist"]?.stringValue ?? ""
    let albumName = obj["albumName"]?.stringValue ?? obj["album"]?.stringValue ?? ""
    let albumArtURL = obj["albumArtURL"]?.stringValue.flatMap { URL(string: $0) }
        ?? obj["albumArt"]?.stringValue.flatMap { URL(string: $0) }
    let durationMs = obj["durationMs"]?.intValue ?? 0
    return Track(id: id, name: name, artist: artist, albumName: albumName, albumArtURL: albumArtURL, durationMs: durationMs)
}

private func parseTracks(from array: [JSONValue]) -> [Track] {
    array.compactMap { parseTrack(from: $0) }
}

// MARK: - SyncMessage → Server JSON (outbound)

extension SyncMessage {
    /// Encodes this message into the flat JSON envelope format the server expects.
    func toServerJSON() throws -> Data {
        var envelope: [String: Any] = [:]

        switch type {
        case .playPrepare(let trackID, let prepareDeadline):
            envelope["type"] = "playPrepare"
            envelope["data"] = [
                "trackId": trackID,
                "track": ["id": trackID],
                "prepareDeadline": prepareDeadline,
            ] as [String: Any]

        case .playCommit(let trackID, let startAtNtp, _):
            envelope["type"] = "playCommit"
            envelope["data"] = [
                "trackId": trackID,
                "ntpTimestamp": startAtNtp,
                "positionMs": 0,
            ] as [String: Any]

        case .pause(let atNtp):
            envelope["type"] = "pause"
            envelope["data"] = ["ntpTimestamp": atNtp]

        case .resume(let atNtp):
            envelope["type"] = "resume"
            envelope["data"] = ["executionTime": atNtp]

        case .seek(let positionMs, let atNtp):
            envelope["type"] = "seek"
            envelope["data"] = [
                "positionMs": positionMs,
                "ntpTimestamp": atNtp,
            ] as [String: Any]

        case .skip:
            envelope["type"] = "skip"
            envelope["data"] = [String: Any]()

        case .driftReport(let trackID, let positionMs, let ntpTimestamp):
            envelope["type"] = "driftReport"
            envelope["data"] = [
                "trackId": trackID,
                "positionMs": positionMs,
                "ntpTimestamp": ntpTimestamp,
            ] as [String: Any]

        case .stateSync, .queueUpdate, .memberJoined, .memberLeft:
            // These are server-to-client only; client never sends them
            break
        }

        return try JSONSerialization.data(withJSONObject: envelope)
    }
}

// MARK: - JSONValue (lightweight dynamic JSON type)

/// A simple JSON value type for decoding the server's freeform `data` fields
/// without pulling in external dependencies.
enum JSONValue: Sendable, Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    // Convenience accessors
    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var doubleValue: Double? {
        if case .number(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case .number(let v) = self { return Int(v) }
        return nil
    }

    var uint64Value: UInt64? {
        if case .number(let v) = self { return UInt64(v) }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let v) = self { return v }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let v) = self { return v }
        return nil
    }

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}
