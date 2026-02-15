import express from "express";
import { createServer } from "http";
import { WebSocketServer } from "ws";
import jwt from "jsonwebtoken";
import crypto from "crypto";

// --- Configuration ---

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || crypto.randomBytes(32).toString("hex");
const JWT_EXPIRY = "24h";
const MAX_MEMBERS = 10;
const MAX_SESSIONS_PER_USER_PER_HOUR = 5;
const MAX_JOIN_ATTEMPTS_PER_IP_PER_MIN = 10;
const PING_INTERVAL_MS = 15_000;
const PONG_TIMEOUT_MS = 5_000;
const SESSION_IDLE_TIMEOUT_MS = 30 * 60 * 1000; // 30 minutes
const CODE_EXPIRY_MS = 60 * 60 * 1000; // 1 hour

// --- In-Memory State ---

/** @type {Map<string, Session>} sessionId → Session */
const sessions = new Map();

/** @type {Map<string, string>} joinCode → sessionId */
const codeIndex = new Map();

/** @type {Map<string, number[]>} userId → creation timestamps */
const sessionCreationLog = new Map();

/** @type {Map<string, number[]>} ip → attempt timestamps */
const joinAttemptLog = new Map();

/**
 * @typedef {Object} Session
 * @property {string} id
 * @property {string} joinCode
 * @property {string} creatorId
 * @property {string} djUserId
 * @property {Map<string, MemberConnection>} members
 * @property {number} epoch
 * @property {number} sequence
 * @property {Object|null} currentTrack
 * @property {boolean} isPlaying
 * @property {number} positionMs - NTP-anchored position
 * @property {number} positionTimestamp - NTP time when position was recorded
 * @property {Array} queue
 * @property {number} lastActivity
 * @property {number} codeCreatedAt
 */

/**
 * @typedef {Object} MemberConnection
 * @property {string} userId
 * @property {string} displayName
 * @property {import('ws').WebSocket} ws
 * @property {boolean} alive
 * @property {number} joinedAt
 */

// --- Express App ---

const app = express();
app.use(express.json());

// Health check
app.get("/health", (_req, res) => {
  res.json({ status: "ok", sessions: sessions.size });
});

// Authenticate: client sends Spotify user info, gets a JWT
app.post("/auth", (req, res) => {
  const { spotifyUserId, displayName } = req.body;
  if (!spotifyUserId || typeof spotifyUserId !== "string") {
    return res.status(400).json({ error: "spotifyUserId required" });
  }

  const token = jwt.sign(
    { sub: spotifyUserId, name: displayName || spotifyUserId },
    JWT_SECRET,
    { expiresIn: JWT_EXPIRY }
  );
  res.json({ token });
});

// Create session
app.post("/sessions", authenticateHTTP, (req, res) => {
  const userId = req.user.sub;

  // Rate limit: 5 sessions/user/hour
  if (!checkRateLimit(sessionCreationLog, userId, MAX_SESSIONS_PER_USER_PER_HOUR, 60 * 60 * 1000)) {
    return res.status(429).json({ error: "Too many sessions created. Try again later." });
  }

  const session = createSession(userId);
  recordRateLimit(sessionCreationLog, userId);

  res.status(201).json({
    id: session.id,
    joinCode: session.joinCode,
    creatorId: session.creatorId,
    djUserId: session.djUserId,
  });
});

// Join session (validate code)
app.post("/sessions/join", authenticateHTTP, (req, res) => {
  const ip = req.ip || req.socket.remoteAddress;
  const { code } = req.body;

  // Rate limit: 10 join attempts/IP/min
  if (!checkRateLimit(joinAttemptLog, ip, MAX_JOIN_ATTEMPTS_PER_IP_PER_MIN, 60 * 1000)) {
    return res.status(429).json({ error: "Too many join attempts. Try again later." });
  }
  recordRateLimit(joinAttemptLog, ip);

  if (!code || typeof code !== "string") {
    return res.status(400).json({ error: "code required" });
  }

  const sessionId = codeIndex.get(code);
  if (!sessionId) {
    return res.status(404).json({ error: "Session not found" });
  }

  const session = sessions.get(sessionId);
  if (!session) {
    codeIndex.delete(code);
    return res.status(404).json({ error: "Session not found" });
  }

  // Check code expiry
  if (Date.now() - session.codeCreatedAt > CODE_EXPIRY_MS) {
    return res.status(410).json({ error: "Join code expired" });
  }

  if (session.members.size >= MAX_MEMBERS) {
    return res.status(409).json({ error: "Session is full" });
  }

  const djMember = session.members.get(session.djUserId);
  res.json({
    id: session.id,
    joinCode: session.joinCode,
    djUserId: session.djUserId,
    djDisplayName: djMember?.displayName || session.djUserId,
    memberCount: session.members.size,
  });
});

// Get session snapshot (for reconnection / join-mid-song)
app.get("/sessions/:id", authenticateHTTP, (req, res) => {
  const session = sessions.get(req.params.id);
  if (!session) {
    return res.status(404).json({ error: "Session not found" });
  }

  res.json(sessionSnapshot(session));
});

// --- WebSocket Server ---

const server = createServer(app);
const wss = new WebSocketServer({ noServer: true });

server.on("upgrade", (request, socket, head) => {
  // Authenticate WebSocket upgrade via query param token
  const url = new URL(request.url, `http://${request.headers.host}`);
  const token = url.searchParams.get("token");
  const sessionId = url.searchParams.get("sessionId");

  if (!token || !sessionId) {
    socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
    socket.destroy();
    return;
  }

  let user;
  try {
    user = jwt.verify(token, JWT_SECRET);
  } catch {
    socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
    socket.destroy();
    return;
  }

  const session = sessions.get(sessionId);
  if (!session) {
    socket.write("HTTP/1.1 404 Not Found\r\n\r\n");
    socket.destroy();
    return;
  }

  wss.handleUpgrade(request, socket, head, (ws) => {
    ws.user = user;
    ws.sessionId = sessionId;
    wss.emit("connection", ws, request);
  });
});

wss.on("connection", (ws) => {
  const { sessionId } = ws;
  const userId = ws.user.sub;
  const displayName = ws.user.name || userId;
  const session = sessions.get(sessionId);

  if (!session) {
    ws.close(4004, "Session not found");
    return;
  }

  if (session.members.size >= MAX_MEMBERS && !session.members.has(userId)) {
    ws.close(4009, "Session full");
    return;
  }

  // Register member
  const existingMember = session.members.get(userId);
  if (existingMember?.ws?.readyState === 1) {
    // Close old connection (reconnect scenario)
    existingMember.ws.close(4000, "Replaced by new connection");
  }

  session.members.set(userId, {
    userId,
    displayName,
    ws,
    alive: true,
    joinedAt: Date.now(),
  });
  session.lastActivity = Date.now();

  // Send session snapshot to joiner
  ws.send(JSON.stringify({
    type: "stateSync",
    data: sessionSnapshot(session),
    epoch: session.epoch,
    seq: session.sequence,
    timestamp: Date.now(),
  }));

  // Notify others
  broadcastToSession(session, {
    type: "memberJoined",
    data: { userId, displayName },
    epoch: session.epoch,
    seq: ++session.sequence,
    timestamp: Date.now(),
  }, userId);

  // Handle messages
  ws.on("message", (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      return; // ignore malformed
    }

    handleMessage(session, userId, msg);
  });

  ws.on("close", () => {
    const member = session.members.get(userId);
    if (member?.ws === ws) {
      session.members.delete(userId);
      broadcastToSession(session, {
        type: "memberLeft",
        data: { userId },
        epoch: session.epoch,
        seq: ++session.sequence,
        timestamp: Date.now(),
      });

      // If DJ left, promote creator or first member
      if (session.djUserId === userId && session.members.size > 0) {
        session.djUserId = session.creatorId && session.members.has(session.creatorId)
          ? session.creatorId
          : session.members.keys().next().value;
        session.epoch++;
        broadcastToSession(session, {
          type: "stateSync",
          data: sessionSnapshot(session),
        });
      }

      // Clean up empty session
      if (session.members.size === 0) {
        destroySession(session.id);
      }
    }
  });

  ws.on("pong", () => {
    const member = session.members.get(userId);
    if (member) member.alive = true;
  });
});

// --- Message Handling ---

function handleMessage(session, senderId, msg) {
  session.lastActivity = Date.now();

  switch (msg.type) {
    case "playPrepare": {
      if (senderId !== session.djUserId) return; // only DJ
      if (!msg.data?.trackId) return;

      session.currentTrack = msg.data.track || { id: msg.data.trackId };
      session.epoch++;
      session.sequence++;

      broadcastToSession(session, {
        type: "playPrepare",
        data: msg.data,
        epoch: session.epoch,
        seq: session.sequence,
        timestamp: Date.now(),
      });
      break;
    }

    case "playCommit": {
      if (senderId !== session.djUserId) return;

      session.isPlaying = true;
      session.positionMs = msg.data?.positionMs || 0;
      session.positionTimestamp = msg.data?.ntpTimestamp || Date.now();
      session.sequence++;

      broadcastToSession(session, {
        type: "playCommit",
        data: msg.data,
        epoch: session.epoch,
        seq: session.sequence,
        timestamp: Date.now(),
      });
      break;
    }

    case "pause": {
      if (senderId !== session.djUserId) return;

      session.isPlaying = false;
      // Snapshot the position at pause time
      if (session.positionTimestamp) {
        const elapsed = Date.now() - session.positionTimestamp;
        session.positionMs += elapsed;
        session.positionTimestamp = Date.now();
      }
      session.sequence++;

      broadcastToSession(session, {
        type: "pause",
        data: { positionMs: session.positionMs, ntpTimestamp: Date.now() },
        epoch: session.epoch,
        seq: session.sequence,
        timestamp: Date.now(),
      });
      break;
    }

    case "resume": {
      if (senderId !== session.djUserId) return;

      session.isPlaying = true;
      session.positionTimestamp = Date.now();
      session.sequence++;

      broadcastToSession(session, {
        type: "resume",
        data: {
          positionMs: session.positionMs,
          ntpTimestamp: Date.now(),
          executionTime: msg.data?.executionTime || Date.now() + 1500,
        },
        epoch: session.epoch,
        seq: session.sequence,
        timestamp: Date.now(),
      });
      break;
    }

    case "seek": {
      if (senderId !== session.djUserId) return;

      session.positionMs = msg.data?.positionMs || 0;
      session.positionTimestamp = Date.now();
      session.sequence++;

      broadcastToSession(session, {
        type: "seek",
        data: msg.data,
        epoch: session.epoch,
        seq: session.sequence,
        timestamp: Date.now(),
      });
      break;
    }

    case "skip": {
      if (senderId !== session.djUserId) return;

      const nextTrack = session.queue.shift();
      if (nextTrack) {
        session.currentTrack = nextTrack;
        session.positionMs = 0;
        session.positionTimestamp = Date.now();
        session.isPlaying = true;
        session.epoch++;
        session.sequence++;

        broadcastToSession(session, {
          type: "playPrepare",
          data: { trackId: nextTrack.id, track: nextTrack },
          epoch: session.epoch,
          seq: session.sequence,
          timestamp: Date.now(),
        });
      }
      break;
    }

    case "addToQueue": {
      if (!msg.data?.track || !msg.data?.nonce) return;
      // Idempotency: check nonce
      if (session.queue.some((t) => t.nonce === msg.data.nonce)) return;

      const queueEntry = { ...msg.data.track, nonce: msg.data.nonce, addedBy: senderId };
      session.queue.push(queueEntry);
      session.sequence++;

      broadcastToSession(session, {
        type: "queueUpdate",
        data: { queue: session.queue },
        epoch: session.epoch,
        seq: session.sequence,
        timestamp: Date.now(),
      });
      break;
    }

    case "removeFromQueue": {
      if (senderId !== session.djUserId) return;
      if (!msg.data?.trackId) return;

      session.queue = session.queue.filter((t) => t.id !== msg.data.trackId);
      session.sequence++;

      broadcastToSession(session, {
        type: "queueUpdate",
        data: { queue: session.queue },
        epoch: session.epoch,
        seq: session.sequence,
        timestamp: Date.now(),
      });
      break;
    }

    case "driftReport": {
      // Client reports its drift — relay to DJ for monitoring
      const djMember = session.members.get(session.djUserId);
      if (djMember?.ws?.readyState === 1) {
        djMember.ws.send(JSON.stringify({
          type: "driftReport",
          data: { ...msg.data, fromUserId: senderId },
          timestamp: Date.now(),
        }));
      }
      break;
    }

    case "ping": {
      // Clock sync ping — respond immediately with server timestamp
      const member = session.members.get(senderId);
      if (member?.ws?.readyState === 1) {
        member.ws.send(JSON.stringify({
          type: "pong",
          data: {
            clientSendTime: msg.data?.clientSendTime,
            serverTime: Date.now(),
          },
        }));
      }
      break;
    }
  }
}

// --- Helpers ---

function createSession(creatorId) {
  const id = crypto.randomUUID();
  const joinCode = generateJoinCode();

  const session = {
    id,
    joinCode,
    creatorId,
    djUserId: creatorId,
    members: new Map(),
    epoch: 0,
    sequence: 0,
    currentTrack: null,
    isPlaying: false,
    positionMs: 0,
    positionTimestamp: 0,
    queue: [],
    lastActivity: Date.now(),
    codeCreatedAt: Date.now(),
  };

  sessions.set(id, session);
  codeIndex.set(joinCode, id);
  return session;
}

function destroySession(sessionId) {
  const session = sessions.get(sessionId);
  if (!session) return;
  codeIndex.delete(session.joinCode);
  sessions.delete(sessionId);
}

function generateJoinCode() {
  let code;
  do {
    code = String(Math.floor(1000 + Math.random() * 9000)); // 4-digit, 1000-9999
  } while (codeIndex.has(code));
  return code;
}

function sessionSnapshot(session) {
  return {
    id: session.id,
    joinCode: session.joinCode,
    creatorId: session.creatorId,
    djUserId: session.djUserId,
    members: Array.from(session.members.values()).map((m) => ({
      userId: m.userId,
      displayName: m.displayName,
    })),
    epoch: session.epoch,
    sequence: session.sequence,
    currentTrack: session.currentTrack,
    isPlaying: session.isPlaying,
    positionMs: session.positionMs,
    positionTimestamp: session.positionTimestamp,
    queue: session.queue,
  };
}

function broadcastToSession(session, message, excludeUserId = null) {
  const payload = JSON.stringify(message);
  for (const [userId, member] of session.members) {
    if (userId === excludeUserId) continue;
    if (member.ws.readyState === 1) {
      member.ws.send(payload);
    }
  }
}

function authenticateHTTP(req, res, next) {
  const auth = req.headers.authorization;
  if (!auth?.startsWith("Bearer ")) {
    return res.status(401).json({ error: "Authorization required" });
  }

  try {
    req.user = jwt.verify(auth.slice(7), JWT_SECRET);
    next();
  } catch {
    res.status(401).json({ error: "Invalid token" });
  }
}

function checkRateLimit(log, key, maxCount, windowMs) {
  const now = Date.now();
  const timestamps = log.get(key) || [];
  const recent = timestamps.filter((t) => now - t < windowMs);
  return recent.length < maxCount;
}

function recordRateLimit(log, key) {
  const timestamps = log.get(key) || [];
  timestamps.push(Date.now());
  log.set(key, timestamps.slice(-20)); // keep last 20 entries max
}

// --- Ping/Pong + Idle Cleanup ---

setInterval(() => {
  const now = Date.now();

  for (const [sessionId, session] of sessions) {
    // Idle timeout
    if (now - session.lastActivity > SESSION_IDLE_TIMEOUT_MS) {
      for (const member of session.members.values()) {
        member.ws.close(4008, "Session idle timeout");
      }
      destroySession(sessionId);
      continue;
    }

    // Ping all members
    for (const [userId, member] of session.members) {
      if (!member.alive) {
        member.ws.terminate();
        session.members.delete(userId);
        broadcastToSession(session, {
          type: "memberLeft",
          data: { userId },
          epoch: session.epoch,
          seq: ++session.sequence,
          timestamp: now,
        });
        continue;
      }
      member.alive = false;
      member.ws.ping();
    }

    if (session.members.size === 0) {
      destroySession(sessionId);
    }
  }
}, PING_INTERVAL_MS);

// --- Rate limit cleanup every 5 minutes ---

setInterval(() => {
  const now = Date.now();
  for (const [key, timestamps] of sessionCreationLog) {
    const recent = timestamps.filter((t) => now - t < 60 * 60 * 1000);
    if (recent.length === 0) sessionCreationLog.delete(key);
    else sessionCreationLog.set(key, recent);
  }
  for (const [key, timestamps] of joinAttemptLog) {
    const recent = timestamps.filter((t) => now - t < 60 * 1000);
    if (recent.length === 0) joinAttemptLog.delete(key);
    else joinAttemptLog.set(key, recent);
  }
}, 5 * 60 * 1000);

// --- Start ---

server.listen(PORT, () => {
  console.log(`[PirateRadio] Server listening on port ${PORT}`);
});
