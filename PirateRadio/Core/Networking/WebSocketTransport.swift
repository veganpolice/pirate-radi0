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
                    await self?.handleDisconnection(error: error)
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

        // Guard against oversized messages (DoS protection)
        guard data.count <= 512_000 else {
            print("[WebSocket] Message too large (\(data.count) bytes), dropping")
            return
        }

        guard let serverMessage = try? JSONDecoder().decode(ServerMessage.self, from: data) else {
            print("[WebSocket] Failed to decode server message: \(String(data: data, encoding: .utf8) ?? "?")")
            return
        }

        guard let syncMessage = Self.translate(serverMessage, rawData: data) else {
            print("[WebSocket] Unhandled server message type: \(serverMessage.type)")
            return
        }

        // Track sequence numbers for reconnection
        if syncMessage.sequenceNumber > lastSeenSeq {
            lastSeenSeq = syncMessage.sequenceNumber
        }
        if syncMessage.epoch > lastSeenEpoch {
            lastSeenEpoch = syncMessage.epoch
        }

        messageContinuation.yield(syncMessage)
    }

    // MARK: - Server → Client Translation

    private static func translate(_ msg: ServerMessage, rawData: Data) -> SyncMessage? {
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

        case "playPrepare":
            let trackID = d?["trackId"]?.stringValue ?? d?["trackID"]?.stringValue ?? ""
            let deadline = UInt64(d?["prepareDeadline"]?.doubleValue ?? 0)
            type = .playPrepare(trackID: trackID, prepareDeadline: deadline)

        case "playCommit":
            let trackID = d?["trackId"]?.stringValue ?? d?["trackID"]?.stringValue ?? ""
            let startAt = UInt64(d?["ntpTimestamp"]?.doubleValue ?? d?["startAtNtp"]?.doubleValue ?? 0)
            let refSeq = UInt64(d?["refSeq"]?.doubleValue ?? 0)
            type = .playCommit(trackID: trackID, startAtNtp: startAt, refSeq: refSeq)

        case "pause":
            let atNtp = UInt64(d?["ntpTimestamp"]?.doubleValue ?? Double(ts))
            type = .pause(atNtp: atNtp)

        case "resume":
            let atNtp = UInt64(d?["executionTime"]?.doubleValue ?? d?["ntpTimestamp"]?.doubleValue ?? Double(ts))
            type = .resume(atNtp: atNtp)

        case "seek":
            let posMs = d?["positionMs"]?.intValue ?? 0
            let atNtp = UInt64(d?["ntpTimestamp"]?.doubleValue ?? Double(ts))
            type = .seek(positionMs: posMs, atNtp: atNtp)

        case "queueUpdate":
            var trackIDs: [String] = []
            if let queueArray = d?["queue"]?.arrayValue {
                for item in queueArray {
                    if let id = item["id"]?.stringValue {
                        trackIDs.append(id)
                    } else if let id = item.stringValue {
                        trackIDs.append(id)
                    }
                }
            }
            type = .queueUpdate(trackIDs)

        case "driftReport":
            let trackID = d?["trackId"]?.stringValue ?? ""
            let posMs = d?["positionMs"]?.intValue ?? 0
            let ntpTs = UInt64(d?["ntpTimestamp"]?.doubleValue ?? 0)
            type = .driftReport(trackID: trackID, positionMs: posMs, ntpTimestamp: ntpTs)

        case "pong":
            // Clock sync response — not a SyncMessage, ignore here
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

    private static func translateStateSync(_ data: JSONValue?, rawData: Data) -> SyncMessage.SyncMessageType? {
        guard let d = data else { return nil }

        // Parse the stateSync data into a SessionSnapshot
        let trackID = d["currentTrack"]?["id"]?.stringValue
        let positionMs = d["positionMs"]?.doubleValue ?? 0
        let positionTimestamp = UInt64(d["positionTimestamp"]?.doubleValue ?? 0)
        let isPlaying = d["isPlaying"]?.boolValue ?? false
        let djUserID = d["djUserId"]?.stringValue ?? ""
        let epoch = UInt64(d["epoch"]?.doubleValue ?? 0)
        let sequence = UInt64(d["sequence"]?.doubleValue ?? 0)

        // Parse queue — array of track objects with id field
        var queue: [String] = []
        if let queueArray = d["queue"]?.arrayValue {
            for item in queueArray {
                if let id = item["id"]?.stringValue {
                    queue.append(id)
                } else if let id = item.stringValue {
                    queue.append(id)
                }
            }
        }

        // Parse members
        var members: [SessionSnapshot.SnapshotMember] = []
        if let membersArray = d["members"]?.arrayValue {
            for m in membersArray {
                let userId = m["userId"]?.stringValue ?? ""
                let displayName = m["displayName"]?.stringValue ?? userId
                members.append(SessionSnapshot.SnapshotMember(userId: userId, displayName: displayName))
            }
        }

        // Try to decode currentTrack as a full Track object
        var currentTrack: Track?
        if let currentTrackValue = d["currentTrack"], currentTrackValue.objectValue?["id"] != nil {
            // Re-encode just the track portion and try Codable decode
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
            djUserID: djUserID,
            epoch: epoch,
            sequenceNumber: sequence,
            members: members,
            currentTrack: currentTrack
        )

        return .stateSync(snapshot)
    }

    /// Convert JSONValue to Any for JSONSerialization interop.
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

    // MARK: - Client → Server Encoding

    static func encodeForServer(_ message: SyncMessage) -> [String: Any] {
        var result: [String: Any] = [
            "seq": message.sequenceNumber,
            "epoch": message.epoch,
            "timestamp": message.timestamp,
        ]

        switch message.type {
        case .playPrepare(let trackID, let deadline):
            result["type"] = "playPrepare"
            result["data"] = ["trackId": trackID, "prepareDeadline": deadline]

        case .playCommit(let trackID, let startAtNtp, let refSeq):
            result["type"] = "playCommit"
            result["data"] = ["trackId": trackID, "ntpTimestamp": startAtNtp, "refSeq": refSeq]

        case .pause(let atNtp):
            result["type"] = "pause"
            result["data"] = ["ntpTimestamp": atNtp]

        case .resume(let atNtp):
            result["type"] = "resume"
            result["data"] = ["executionTime": atNtp, "ntpTimestamp": atNtp]

        case .seek(let positionMs, let atNtp):
            result["type"] = "seek"
            result["data"] = ["positionMs": positionMs, "ntpTimestamp": atNtp]

        case .skip:
            result["type"] = "skip"
            result["data"] = [String: Any]()

        case .driftReport(let trackID, let positionMs, let ntpTimestamp):
            result["type"] = "driftReport"
            result["data"] = ["trackId": trackID, "positionMs": positionMs, "ntpTimestamp": ntpTimestamp]

        case .stateSync, .queueUpdate, .memberJoined, .memberLeft:
            // These are server-originated; client doesn't send them
            result["type"] = "unknown"
            result["data"] = [String: Any]()
        }

        return result
    }

    // MARK: - Reconnection

    private func handleDisconnection(error: Error) {
        guard shouldStayConnected, !isReconnecting else { return }

        webSocketTask = nil
        isReconnecting = true

        Task {
            while shouldStayConnected && reconnectAttempt < maxReconnectAttempts {
                reconnectAttempt += 1
                stateContinuation.yield(.reconnecting(attempt: reconnectAttempt))

                // Exponential backoff: 0.5s, 1s, 2s, 4s, 8s, cap at 15s
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
