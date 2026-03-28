import express from "express";
import { createServer } from "http";
import { WebSocketServer } from "ws";
import jwt from "jsonwebtoken";
import crypto from "crypto";
import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { initDB, STATIONS, loadStations, persistStation, closeDB } from "./db.js";

// --- Configuration ---

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || crypto.randomBytes(32).toString("hex");
const JWT_EXPIRY = "24h";
const MAX_MEMBERS = 50;
const PING_INTERVAL_MS = 15_000;
const MAX_TRACK_DURATION_MS = 30 * 60 * 1000; // 30 minutes — clamp for timer safety
const MAX_QUEUE_SIZE = 100;
const MAX_HISTORY_SIZE = 200; // cap history to prevent unbounded memory growth
const SKIP_COOLDOWN_MS = 3_000; // 1 skip per 3 seconds per station
const VOICE_CLIP_MAX_BYTES = 60_000; // 60KB max for a single voice clip frame
const VOICE_CLIP_COOLDOWN_MS = 15_000; // 1 clip per 15 seconds per user
const VOICE_CLIP_MAX_DURATION_MS = 10_000; // 10 seconds max recording

// --- In-Memory State ---

/** @type {Map<string, Station>} stationId → Station */
const stations = new Map();

/**
 * @typedef {Object} Station
 * @property {string} id
 * @property {string} name
 * @property {number} frequency
 * @property {Map<string, MemberConnection>} members
 * @property {number} epoch
 * @property {number} sequence
 * @property {Object|null} currentTrack
 * @property {boolean} isPlaying
 * @property {number} positionMs - NTP-anchored position
 * @property {number} positionTimestamp - NTP time when position was recorded
 * @property {Array} queue
 * @property {Array} history - previously played tracks (for looping)
 * @property {NodeJS.Timeout|null} advancementTimer - server-side queue advancement timer
 */

/**
 * @typedef {Object} MemberConnection
 * @property {string} userId
 * @property {string} displayName
 * @property {import('ws').WebSocket} ws
 * @property {boolean} alive
 * @property {number} joinedAt
 */

// --- Boot Stations ---

function bootStations() {
  const db = initDB();
  const persisted = loadStations();
  const persistedMap = new Map(persisted.map((s) => [s.id, s]));

  for (const def of STATIONS) {
    const existing = persistedMap.get(def.id);
    const station = {
      id: def.id,
      name: def.name,
      frequency: def.frequency,
      members: new Map(),
      epoch: existing?.epoch || 0,
      sequence: existing?.sequence || 0,
      currentTrack: existing?.currentTrack || null,
      isPlaying: existing?.isPlaying || false,
      positionMs: existing?.positionMs || 0,
      positionTimestamp: existing?.positionTimestamp || 0,
      queue: existing?.queue || [],
      history: existing?.history || [],
      advancementTimer: null,
      lastSkipTime: 0,
    };

    stations.set(def.id, station);

    if (!existing) {
      persistStation(station);
    }

    // Restore advancement timer for stations that were playing
    if (station.isPlaying && station.currentTrack) {
      scheduleAdvancement(station);
    }
  }

  console.log(`[boot] ${stations.size} stations loaded`);
}

// --- Express App ---

const app = express();
app.use(express.json());

// CORS
app.use((req, res, next) => {
  res.header("Access-Control-Allow-Origin", "*");
  res.header("Access-Control-Allow-Headers", "Authorization, Content-Type");
  res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});

// Health check
app.get("/health", (_req, res) => {
  res.json({ status: "ok", stations: stations.size });
});

// Admin: list all stations
app.get("/admin/stations", (_req, res) => {
  const result = [];
  for (const station of stations.values()) {
    result.push({
      id: station.id,
      name: station.name,
      frequency: station.frequency,
      members: Array.from(station.members.values()).map((m) => ({
        userId: m.userId,
        displayName: m.displayName,
        joinedAt: m.joinedAt,
        alive: m.alive,
      })),
      epoch: station.epoch,
      sequence: station.sequence,
      currentTrack: station.currentTrack,
      isPlaying: station.isPlaying,
      positionMs: station.positionMs,
      positionTimestamp: station.positionTimestamp,
      queue: station.queue,
      historyLength: station.history.length,
    });
  }
  res.json({ stations: result, serverTime: Date.now() });
});

// Monitor dashboard
const __dirname = dirname(fileURLToPath(import.meta.url));
const monitorHTML = readFileSync(join(__dirname, "monitor.html"), "utf-8");
app.get("/monitor", (_req, res) => {
  res.type("html").send(monitorHTML);
});

// Authenticate: client sends Spotify user info, gets a JWT
app.post("/auth", (req, res) => {
  const { spotifyUserId, displayName } = req.body;
  console.log(`[auth] ${displayName || spotifyUserId}`);
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

// List all stations (always returns all 5)
app.get("/stations", authenticateHTTP, (_req, res) => {
  const result = [];
  for (const station of stations.values()) {
    result.push({
      id: station.id,
      name: station.name,
      frequency: station.frequency,
      currentTrack: station.currentTrack,
      isPlaying: station.isPlaying,
      listenerCount: station.members.size,
      queueLength: station.queue.length,
    });
  }
  res.json({ stations: result });
});

// Get station snapshot (for reconnection / join-mid-song)
app.get("/stations/:id", authenticateHTTP, (req, res) => {
  const station = stations.get(req.params.id);
  if (!station) {
    return res.status(404).json({ error: "Station not found" });
  }
  res.json(stationSnapshot(station));
});

// --- WebSocket Server ---

const server = createServer(app);
const wss = new WebSocketServer({ noServer: true, maxPayload: 512_000 });

server.on("upgrade", (request, socket, head) => {
  const url = new URL(request.url, `http://${request.headers.host}`);
  const token = url.searchParams.get("token");
  const stationId = url.searchParams.get("sessionId") || url.searchParams.get("stationId");

  if (!token || !stationId) {
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

  const station = stations.get(stationId);
  if (!station) {
    socket.write("HTTP/1.1 404 Not Found\r\n\r\n");
    socket.destroy();
    return;
  }

  wss.handleUpgrade(request, socket, head, (ws) => {
    ws.user = user;
    ws.stationId = stationId;
    wss.emit("connection", ws, request);
  });
});

wss.on("connection", (ws) => {
  const { stationId } = ws;
  const userId = ws.user.sub;
  const displayName = ws.user.name || userId;
  const station = stations.get(stationId);

  if (!station) {
    ws.close(4004, "Station not found");
    return;
  }

  if (station.members.size >= MAX_MEMBERS && !station.members.has(userId)) {
    ws.close(4009, "Station full");
    return;
  }

  // Replace existing connection (reconnect scenario)
  const existingMember = station.members.get(userId);
  if (existingMember?.ws?.readyState === 1) {
    existingMember.ws.close(4000, "Replaced by new connection");
  }

  station.members.set(userId, {
    userId,
    displayName,
    ws,
    alive: true,
    joinedAt: Date.now(),
  });
  console.log(`[ws] connected: ${displayName} (${userId}) to ${station.name}, members=${station.members.size}`);

  // Send station snapshot to joiner
  ws.send(JSON.stringify({
    type: "stateSync",
    data: stationSnapshot(station),
    epoch: station.epoch,
    seq: station.sequence,
    timestamp: Date.now(),
  }));

  // Notify others
  broadcastToStation(station, {
    type: "memberJoined",
    data: { userId, displayName },
    epoch: station.epoch,
    seq: ++station.sequence,
    timestamp: Date.now(),
  }, userId);

  // Handle messages
  ws.on("message", (raw, isBinary) => {
    // Voice clip: single binary frame with 4-byte length-prefixed JSON header + audio
    if (isBinary) {
      handleVoiceClip(station, userId, displayName, raw);
      return;
    }

    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      return;
    }
    console.log(`[ws:msg] ${displayName}: ${msg.type}`, msg.data ? JSON.stringify(msg.data).slice(0, 120) : "");
    handleMessage(station, userId, msg);
  });

  ws.on("close", () => {
    const member = station.members.get(userId);
    if (member?.ws === ws) {
      station.members.delete(userId);
      broadcastToStation(station, {
        type: "memberLeft",
        data: { userId },
        epoch: station.epoch,
        seq: ++station.sequence,
        timestamp: Date.now(),
      });
    }
  });

  ws.on("pong", () => {
    const member = station.members.get(userId);
    if (member) member.alive = true;
  });
});

// --- Message Handling ---

function handleMessage(station, senderId, msg) {
  switch (msg.type) {
    case "skip": {
      const now = Date.now();
      if (now - station.lastSkipTime < SKIP_COOLDOWN_MS) return;
      station.lastSkipTime = now;
      advanceQueue(station);
      break;
    }

    case "addToQueue": {
      if (!msg.data?.track || !msg.data?.nonce) return;
      // Validate track has a usable duration (prevent wedged stations)
      const dur = Number(msg.data.track.durationMs);
      if (!Number.isFinite(dur) || dur <= 0 || dur > MAX_TRACK_DURATION_MS) return;
      if (station.queue.length >= MAX_QUEUE_SIZE) return;
      // Idempotency: check nonce across queue, current track, and history
      if (station.queue.some((t) => t.nonce === msg.data.nonce)) return;
      if (station.currentTrack?.nonce === msg.data.nonce) return;
      if (station.history.some((t) => t.nonce === msg.data.nonce)) return;

      const queueEntry = { ...msg.data.track, nonce: msg.data.nonce, addedBy: senderId };
      station.queue.push(queueEntry);
      station.sequence++;

      broadcastToStation(station, {
        type: "queueUpdate",
        data: { queue: station.queue },
        epoch: station.epoch,
        seq: station.sequence,
        timestamp: Date.now(),
      });

      persistStation(station);

      // Auto-start: if station is idle, begin playback
      if (!station.isPlaying) {
        advanceQueue(station);
      }
      break;
    }

    case "ping": {
      const member = station.members.get(senderId);
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

// --- Voice Clip Handling ---

function handleVoiceClip(station, senderId, displayName, raw) {
  // Validate minimum size: 4-byte header + at least 1 byte JSON + 1 byte audio
  if (raw.length < 6) return;
  if (raw.length > VOICE_CLIP_MAX_BYTES) {
    console.log(`[voiceClip] Rejected from ${displayName}: too large (${raw.length} bytes)`);
    return;
  }

  const member = station.members.get(senderId);
  if (!member) return;

  // Rate limit
  const now = Date.now();
  if (member.lastVoiceClipTime && now - member.lastVoiceClipTime < VOICE_CLIP_COOLDOWN_MS) {
    console.log(`[voiceClip] Rate limited ${displayName}`);
    return;
  }

  // Parse header: first 4 bytes = uint32 BE JSON length
  const jsonLen = raw.readUInt32BE(0);
  if (jsonLen < 2 || jsonLen > 1024 || 4 + jsonLen >= raw.length) return;

  let metadata;
  try {
    metadata = JSON.parse(raw.slice(4, 4 + jsonLen).toString("utf8"));
  } catch {
    return;
  }

  if (metadata.type !== "voiceClip") return;
  if (!metadata.clipId || String(metadata.clipId).length > 64) return;

  const durationMs = Number(metadata.durationMs);
  if (!Number.isFinite(durationMs) || durationMs <= 0 || durationMs > VOICE_CLIP_MAX_DURATION_MS) return;

  // Inject server-authoritative sender info
  metadata.senderId = senderId;
  metadata.senderName = displayName;

  // Repack with injected fields
  const newJson = Buffer.from(JSON.stringify(metadata), "utf8");
  const newHeader = Buffer.alloc(4);
  newHeader.writeUInt32BE(newJson.length, 0);
  const audioData = raw.slice(4 + jsonLen);
  const repacked = Buffer.concat([newHeader, newJson, audioData]);

  // Set rate limit on successful relay
  member.lastVoiceClipTime = now;

  console.log(`[voiceClip] ${displayName}: ${durationMs}ms, ${audioData.length} bytes audio`);

  broadcastBinaryToStation(station, repacked, senderId);
}

function broadcastBinaryToStation(station, buffer, excludeUserId = null) {
  for (const [userId, member] of station.members) {
    if (userId === excludeUserId) continue;
    if (member.ws.readyState === 1) {
      member.ws.send(buffer);
    }
  }
}

// --- Autonomous Queue Advancement ---

function scheduleAdvancement(station) {
  clearAdvancement(station);
  if (!station.currentTrack || !station.isPlaying) return;

  const durationMs = Number(station.currentTrack.durationMs);
  if (!Number.isFinite(durationMs) || durationMs <= 0 || durationMs > MAX_TRACK_DURATION_MS) return;

  const elapsed = Date.now() - station.positionTimestamp;
  const currentPositionMs = station.positionMs + elapsed;
  const remainingMs = durationMs - currentPositionMs;

  if (remainingMs <= 0) {
    setImmediate(() => advanceQueue(station));
    return;
  }

  station.advancementTimer = setTimeout(() => {
    advanceQueue(station);
  }, remainingMs);
}

function clearAdvancement(station) {
  if (station.advancementTimer) {
    clearTimeout(station.advancementTimer);
    station.advancementTimer = null;
  }
}

function advanceQueue(station) {
  clearAdvancement(station);

  // Push current track to history before advancing
  if (station.currentTrack) {
    station.history.push(station.currentTrack);
    // Cap history to prevent unbounded memory growth
    if (station.history.length > MAX_HISTORY_SIZE) {
      station.history = station.history.slice(-MAX_HISTORY_SIZE);
    }
  }

  let nextTrack = station.queue.shift();

  // If queue is empty, loop from history
  if (!nextTrack && station.history.length > 0) {
    // Strip nonces so looped tracks can be re-added by users
    station.queue = station.history.map(({ nonce, ...track }) => track);
    station.history = [];
    nextTrack = station.queue.shift();
  }

  if (nextTrack) {
    station.currentTrack = nextTrack;
    station.positionMs = 0;
    station.positionTimestamp = Date.now();
    station.isPlaying = true;
    station.epoch++;
    station.sequence = 0;

    broadcastToStation(station, {
      type: "stateSync",
      data: stationSnapshot(station),
      epoch: station.epoch,
      seq: station.sequence,
      timestamp: Date.now(),
    });

    persistStation(station);
    scheduleAdvancement(station);
  } else {
    // Truly empty: no queue, no history. Station idles.
    station.currentTrack = null;
    station.isPlaying = false;

    broadcastToStation(station, {
      type: "stateSync",
      data: stationSnapshot(station),
      epoch: station.epoch,
      seq: ++station.sequence,
      timestamp: Date.now(),
    });

    persistStation(station);
  }
}

// --- Helpers ---

function stationSnapshot(station) {
  return {
    id: station.id,
    name: station.name,
    frequency: station.frequency,
    members: Array.from(station.members.values()).map((m) => ({
      userId: m.userId,
      displayName: m.displayName,
    })),
    epoch: station.epoch,
    sequence: station.sequence,
    currentTrack: station.currentTrack,
    isPlaying: station.isPlaying,
    positionMs: station.positionMs,
    positionTimestamp: station.positionTimestamp,
    queue: station.queue,
  };
}

function broadcastToStation(station, message, excludeUserId = null) {
  const payload = JSON.stringify(message);
  for (const [userId, member] of station.members) {
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

// --- Ping/Pong ---

setInterval(() => {
  for (const station of stations.values()) {
    for (const [userId, member] of station.members) {
      if (!member.alive) {
        member.ws.terminate();
        station.members.delete(userId);
        broadcastToStation(station, {
          type: "memberLeft",
          data: { userId },
          epoch: station.epoch,
          seq: ++station.sequence,
          timestamp: Date.now(),
        });
        continue;
      }
      member.alive = false;
      member.ws.ping();
    }
  }
}, PING_INTERVAL_MS);

// --- Start ---

bootStations();

server.listen(PORT, () => {
  console.log(`[PirateRadio] Server listening on port ${PORT}`);
});

// Graceful shutdown
process.on("SIGTERM", () => {
  for (const station of stations.values()) {
    clearAdvancement(station);
    for (const member of station.members.values()) {
      member.ws.close(1001, "Server shutting down");
    }
    persistStation(station);
  }
  closeDB();
  server.close(() => process.exit(0));
  // Force exit after 5s if connections don't close cleanly
  setTimeout(() => process.exit(0), 5000).unref();
});
