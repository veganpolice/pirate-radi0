import Foundation

/// WebSocket-based implementation of SessionTransport.
/// Connects to the Pirate Radio backend using URLSessionWebSocketTask.
/// Handles reconnection with exponential backoff.
actor WebSocketTransport: SessionTransport {
    private let baseURL: URL
    private var webSocketTask: URLSessionWebSocketTask?
    private var sessionID: SessionID?
    private var token: String?

    private let messageContinuation: AsyncStream<SyncMessage>.Continuation
    let incomingMessages: AsyncStream<SyncMessage>

    private let voiceClipContinuation: AsyncStream<IncomingVoiceClip>.Continuation
    let incomingVoiceClips: AsyncStream<IncomingVoiceClip>

    private let stateContinuation: AsyncStream<ConnectionState>.Continuation
    let connectionState: AsyncStream<ConnectionState>

    private var reconnectAttempt = 0
    private var maxReconnectAttempts = 10
    private var isReconnecting = false
    private var shouldStayConnected = false
    private var lastSeenSeq: UInt64 = 0
    private var lastSeenEpoch: UInt64 = 0

    init(baseURL: URL) {
        self.baseURL = baseURL

        let (msgStream, msgCont) = AsyncStream.makeStream(of: SyncMessage.self, bufferingPolicy: .bufferingNewest(50))
        self.incomingMessages = msgStream
        self.messageContinuation = msgCont

        let (clipStream, clipCont) = AsyncStream.makeStream(of: IncomingVoiceClip.self, bufferingPolicy: .bufferingNewest(5))
        self.incomingVoiceClips = clipStream
        self.voiceClipContinuation = clipCont

        let (stateStream, stateCont) = AsyncStream.makeStream(of: ConnectionState.self, bufferingPolicy: .bufferingNewest(1))
        self.connectionState = stateStream
        self.stateContinuation = stateCont
    }

    // MARK: - SessionTransport

    func connect(to session: SessionID, token: String) async throws {
        self.sessionID = session
        self.token = token
        self.shouldStayConnected = true
        self.reconnectAttempt = 0

        try await establishConnection()
    }

    func disconnect() async {
        shouldStayConnected = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        stateContinuation.yield(.disconnected)
    }

    func send(_ message: SyncMessage) async throws {
        guard let task = webSocketTask else {
            throw PirateRadioError.notConnected
        }

        let serverJSON = Self.encodeForServer(message)
        let data = try JSONSerialization.data(withJSONObject: serverJSON)
        try await task.send(.data(data))
    }

    func sendVoiceClip(clipId: String, durationMs: Int, audioData: Data) async throws {
        guard let task = webSocketTask else {
            throw PirateRadioError.notConnected
        }

        let metadata: [String: Any] = [
            "type": "voiceClip",
            "clipId": clipId,
            "durationMs": durationMs,
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: metadata)

        // Pack: 4-byte uint32 BE JSON length + JSON + audio
        var frame = Data(count: 4)
        let jsonLen = UInt32(jsonData.count)
        frame[0] = UInt8((jsonLen >> 24) & 0xFF)
        frame[1] = UInt8((jsonLen >> 16) & 0xFF)
        frame[2] = UInt8((jsonLen >> 8) & 0xFF)
        frame[3] = UInt8(jsonLen & 0xFF)
        frame.append(jsonData)
        frame.append(audioData)

        guard frame.count <= 60_000 else {
            throw PirateRadioError.voiceClipTooLarge
        }

        try await task.send(.data(frame))
    }

    // MARK: - Connection

    private func establishConnection() async throws {
        guard let sessionID, let token else {
            throw PirateRadioError.notAuthenticated
        }

        stateContinuation.yield(.connecting)

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "sessionId", value: sessionID),
        ]

        guard let wsURL = components.url else {
            throw PirateRadioError.sessionNotFound
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: wsURL)
        self.webSocketTask = task
        task.resume()

        stateContinuation.yield(.connected)
        reconnectAttempt = 0

        startReceiving()
    }

    private func startReceiving() {
        guard let task = webSocketTask else { return }

        Task { [weak self] in
            while task.state == .running {
                do {
                    let message = try await task.receive()
                    await self?.handleReceivedMessage(message)
                } catch {
                    let closeCode = task.closeCode.rawValue
                    await self?.handleDisconnection(error: error, closeCode: Int(closeCode))
                    break
                }
            }
        }
    }

    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d):
            data = d
        case .string(let s):
            guard let d = s.data(using: .utf8) else { return }
            data = d
        @unknown default:
            return
        }

        guard data.count <= 512_000 else {
            print("[WebSocket] Message too large (\(data.count) bytes), dropping")
            return
        }

        // Try to decode as JSON first. If it fails, check if it's a voice clip binary frame.
        if let serverMessage = try? JSONDecoder().decode(ServerMessage.self, from: data) {
            guard let syncMessage = Self.translate(serverMessage, rawData: data) else {
                return
            }

            if syncMessage.sequenceNumber > lastSeenSeq {
                lastSeenSeq = syncMessage.sequenceNumber
            }
            if syncMessage.epoch > lastSeenEpoch {
                lastSeenEpoch = syncMessage.epoch
            }

            messageContinuation.yield(syncMessage)
        } else if let clip = Self.parseVoiceClipFrame(data) {
            voiceClipContinuation.yield(clip)
        } else {
            print("[WebSocket] Failed to decode message (\(data.count) bytes)")
        }
    }

    /// Parse a single binary frame as a voice clip: 4-byte header + JSON metadata + audio.
    static func parseVoiceClipFrame(_ data: Data) -> IncomingVoiceClip? {
        guard data.count >= 6, data.count <= 65_536 else { return nil }

        let jsonLen = Int(UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3]))
        guard jsonLen > 0, jsonLen <= 1024, 4 + jsonLen < data.count else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data[4..<(4 + jsonLen)]) as? [String: Any],
              json["type"] as? String == "voiceClip",
              let clipId = json["clipId"] as? String,
              let senderName = json["senderName"] as? String,
              let durationMs = json["durationMs"] as? Int else {
            return nil
        }

        let audioData = data[(4 + jsonLen)...]
        return IncomingVoiceClip(
            clipId: clipId,
            senderName: senderName,
            durationMs: durationMs,
            audioData: Data(audioData)
        )
    }

    // MARK: - Server → Client Translation

    static func translate(_ msg: ServerMessage, rawData: Data) -> SyncMessage? {
        let seq = msg.seq ?? 0
        let epoch = msg.epoch ?? 0
        let ts = msg.timestamp ?? 0
        let d = msg.data

        let type: SyncMessage.SyncMessageType?

        switch msg.type {
        case "stateSync":
            type = translateStateSync(d, rawData: rawData)

        case "memberJoined":
            let userID = d?["userId"]?.stringValue ?? ""
            let displayName = d?["displayName"]?.stringValue ?? userID
            type = .memberJoined(userID: userID, displayName: displayName)

        case "memberLeft":
            let userID = d?["userId"]?.stringValue ?? ""
            type = .memberLeft(userID)

        case "queueUpdate":
            let tracks = decodeTrackArray(d?["queue"])
            type = .queueUpdate(tracks)

        case "pong":
            return nil

        default:
            return nil
        }

        guard let msgType = type else { return nil }

        return SyncMessage(
            id: UUID(),
            type: msgType,
            sequenceNumber: seq,
            epoch: epoch,
            timestamp: ts
        )
    }

    static func translateStateSync(_ data: JSONValue?, rawData: Data) -> SyncMessage.SyncMessageType? {
        guard let d = data else { return nil }

        let trackID = d["currentTrack"]?["id"]?.stringValue
        let positionMs = d["positionMs"]?.doubleValue ?? 0
        let positionTimestamp = UInt64(d["positionTimestamp"]?.doubleValue ?? 0)
        let isPlaying = d["isPlaying"]?.boolValue ?? false
        let stationName = d["name"]?.stringValue ?? ""
        let epoch = UInt64(d["epoch"]?.doubleValue ?? 0)
        let sequence = UInt64(d["sequence"]?.doubleValue ?? 0)

        let queue = decodeTrackArray(d["queue"])

        var members: [SessionSnapshot.SnapshotMember] = []
        if let membersArray = d["members"]?.arrayValue {
            for m in membersArray {
                let userId = m["userId"]?.stringValue ?? ""
                let displayName = m["displayName"]?.stringValue ?? userId
                members.append(SessionSnapshot.SnapshotMember(userId: userId, displayName: displayName))
            }
        }

        var currentTrack: Track?
        if let currentTrackValue = d["currentTrack"], currentTrackValue.objectValue?["id"] != nil {
            if let trackData = try? JSONSerialization.data(withJSONObject: jsonValueToAny(currentTrackValue) ?? [:]) {
                currentTrack = try? JSONDecoder().decode(Track.self, from: trackData)
            }
        }

        let snapshot = SessionSnapshot(
            trackID: trackID,
            positionAtAnchor: positionMs / 1000.0,
            ntpAnchor: positionTimestamp,
            playbackRate: isPlaying ? 1.0 : 0.0,
            queue: queue,
            stationName: stationName,
            epoch: epoch,
            sequenceNumber: sequence,
            members: members,
            currentTrack: currentTrack
        )

        return .stateSync(snapshot)
    }

    private static func jsonValueToAny(_ value: JSONValue) -> Any? {
        switch value {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .null: return nil
        case .array(let arr): return arr.map { jsonValueToAny($0) ?? NSNull() }
        case .object(let obj):
            var dict: [String: Any] = [:]
            for (k, v) in obj {
                dict[k] = jsonValueToAny(v) ?? NSNull()
            }
            return dict
        }
    }

    private static func decodeTrackArray(_ value: JSONValue?) -> [Track] {
        guard let arr = value?.arrayValue else { return [] }
        return arr.compactMap { item -> Track? in
            guard let dict = jsonValueToAny(item) else { return nil }
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? JSONDecoder().decode(Track.self, from: data)
        }
    }

    // MARK: - Client → Server Encoding

    static func encodeForServer(_ message: SyncMessage) -> [String: Any] {
        var result: [String: Any] = [
            "seq": message.sequenceNumber,
            "epoch": message.epoch,
            "timestamp": message.timestamp,
        ]

        switch message.type {
        case .skip:
            result["type"] = "skip"
            result["data"] = [String: Any]()

        case .addToQueue(let track, let nonce):
            result["type"] = "addToQueue"
            result["data"] = [
                "track": [
                    "id": track.id, "name": track.name, "artist": track.artist,
                    "albumName": track.albumName,
                    "albumArtURL": track.albumArtURL?.absoluteString ?? "",
                    "durationMs": track.durationMs,
                ] as [String: Any],
                "nonce": nonce,
            ] as [String: Any]

        case .stateSync, .queueUpdate, .memberJoined, .memberLeft:
            result["type"] = "unknown"
            result["data"] = [String: Any]()
        }

        return result
    }

    // MARK: - Reconnection

    private func handleDisconnection(error: Error, closeCode: Int = 0) {
        guard shouldStayConnected, !isReconnecting else { return }

        if closeCode == 4004 || closeCode == 4009 {
            let reason = closeCode == 4004 ? "Station no longer exists" : "Station is full"
            print("[WebSocket] Permanent close code \(closeCode): \(reason)")
            webSocketTask = nil
            shouldStayConnected = false
            stateContinuation.yield(.failed(reason))
            return
        }

        webSocketTask = nil
        isReconnecting = true

        Task {
            while shouldStayConnected && reconnectAttempt < maxReconnectAttempts {
                reconnectAttempt += 1
                stateContinuation.yield(.reconnecting(attempt: reconnectAttempt))

                let delay = min(0.5 * pow(2.0, Double(reconnectAttempt - 1)), 15.0)
                try? await Task.sleep(for: .seconds(delay))

                guard shouldStayConnected else { break }

                do {
                    try await establishConnection()
                    isReconnecting = false
                    stateContinuation.yield(.resyncing)
                    return
                } catch {
                    // Continue trying
                }
            }

            isReconnecting = false
            if shouldStayConnected {
                stateContinuation.yield(.failed("Unable to reconnect after \(maxReconnectAttempts) attempts"))
            }
        }
    }

}
