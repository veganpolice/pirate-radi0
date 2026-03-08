import express from "express";
import { createServer } from "http";
import { WebSocketServer } from "ws";
import jwt from "jsonwebtoken";
import crypto from "crypto";
import { createDatabase } from "./db.js";

// --- Configuration ---

const PORT = process.env.PORT || 3000;
const JWT_SECRET =
  process.env.JWT_SECRET || crypto.randomBytes(32).toString("hex");
const JWT_EXPIRY = "24h";
const MAX_MEMBERS = 10;
const MAX_JOIN_ATTEMPTS_PER_IP_PER_MIN = 10;
const PING_INTERVAL_MS = 15_000;
const MAX_TRACK_DURATION_MS = 30 * 60 * 1000; // 30 minutes
const MAX_QUEUE_SIZE = 100;

// --- Database ---

const db = createDatabase(process.env.DB_PATH || ":memory:");

// Prepared statements
const stmtGetStation = db.prepare("SELECT * FROM stations WHERE user_id = ?");
const stmtInsertStation = db.prepare(
  "INSERT INTO stations (user_id, display_name, frequency) VALUES (?, ?, ?)"
);
const stmtUpdateDisplayName = db.prepare(
  "UPDATE stations SET display_name = ? WHERE user_id = ?"
);
const stmtUpdateTracks = db.prepare(
  "UPDATE stations SET tracks_json = ? WHERE user_id = ?"
);
const stmtSaveSnapshot = db.prepare(
  `UPDATE stations SET tracks_json = ?, snapshot_track_index = ?, snapshot_elapsed_ms = ?, snapshot_timestamp = ? WHERE user_id = ?`
);
const stmtAllStations = db.prepare("SELECT * FROM stations");

// --- Helpers ---

/** Safely parse tracks_json, returning [] on corrupt data */
function safeParseTracksJson(json) {
  try {
    const parsed = JSON.parse(json);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

// --- In-Memory State (live sessions only) ---

/** @type {Map<string, LiveSession>} userId → LiveSession */
const liveSessions = new Map();

/** @type {Map<string, number[]>} ip → attempt timestamps */
const joinAttemptLog = new Map();

/**
 * @typedef {Object} LiveSession
 * @property {string} userId - station owner
 * @property {Map<string, MemberConnection>} members
 * @property {number} epoch
 * @property {number} sequence
 * @property {Object|null} currentTrack
 * @property {boolean} isPlaying
 * @property {number} positionMs
 * @property {number} positionTimestamp
 * @property {Array} tracks - the full queue (source of truth while live)
 * @property {number} trackIndex - cursor into tracks array
 * @property {number} lastActivity
 * @property {NodeJS.Timeout|null} advancementTimer
 * @property {NodeJS.Timeout|null} destroyTimeout
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
  try {
    db.prepare("SELECT 1").get();
    res.json({ status: "ok", liveSessions: liveSessions.size });
  } catch {
    res.status(500).json({ status: "error", message: "Database unavailable" });
  }
});

// Authenticate: client sends Spotify user info, gets a JWT
app.post("/auth", (req, res) => {
  const { spotifyUserId, displayName } = req.body;
  console.log(`[auth] ${displayName || spotifyUserId}`);
  if (!spotifyUserId || typeof spotifyUserId !== "string") {
    return res.status(400).json({ error: "spotifyUserId required" });
  }

  const name = displayName || spotifyUserId;
  const existing = stmtGetStation.get(spotifyUserId);

  if (existing) {
    // Update display name if changed
    if (existing.display_name !== name) {
      stmtUpdateDisplayName.run(name, spotifyUserId);
    }
    const token = jwt.sign(
      { sub: spotifyUserId, name },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRY }
    );
    res.json({ token, needsFrequency: false, frequency: existing.frequency });
  } else {
    // No station yet — client must claim a frequency
    const token = jwt.sign(
      { sub: spotifyUserId, name },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRY }
    );
    res.json({ token, needsFrequency: true });
  }
});

// Claim a frequency for a new station
app.post("/stations/claim-frequency", authenticateHTTP, (req, res) => {
  const userId = req.user.sub;
  const displayName = req.user.name || userId;
  const { frequency } = req.body;

  // Validate frequency is an integer in range with correct step
  if (
    typeof frequency !== "number" ||
    !Number.isInteger(frequency) ||
    frequency < 881 ||
    frequency > 1079 ||
    frequency % 2 !== 1
  ) {
    return res.status(400).json({
      error:
        "frequency must be an odd integer between 881 and 1079 (e.g. 881 = 88.1 MHz)",
    });
  }

  // Check if user already has a station
  const existing = stmtGetStation.get(userId);
  if (existing) {
    return res.status(409).json({
      error: "You already have a station",
      frequency: existing.frequency,
    });
  }

  // Try to insert — UNIQUE constraint handles conflicts
  try {
    stmtInsertStation.run(userId, displayName, frequency);
    console.log(`[station] ${displayName} claimed ${frequency / 10} MHz`);
    res.status(201).json({ frequency });
  } catch (err) {
    if (err.code === "SQLITE_CONSTRAINT_UNIQUE") {
      return res.status(409).json({ error: "Frequency already taken" });
    }
    throw err;
  }
});

// List ALL registered stations
app.get("/stations", authenticateHTTP, (_req, res) => {
  const rows = stmtAllStations.all();
  const stations = rows.map((row) => {
    const live = liveSessions.get(row.user_id);
    if (live) {
      return {
        userId: row.user_id,
        displayName: row.display_name,
        frequency: row.frequency,
        currentTrack: live.currentTrack,
        trackCount: live.tracks.length,
        listenerCount: live.members.size,
        isLive: true,
        ownerConnected: live.members.has(row.user_id),
      };
    }
    // Idle station — derive currentTrack from snapshot
    const tracks = safeParseTracksJson(row.tracks_json);
    const idx = Math.min(row.snapshot_track_index, Math.max(0, tracks.length - 1));
    return {
      userId: row.user_id,
      displayName: row.display_name,
      frequency: row.frequency,
      currentTrack: tracks[idx] || null,
      trackCount: tracks.length,
      listenerCount: 0,
      isLive: false,
      ownerConnected: false,
    };
  });
  res.json({ stations });
});

// Join a station by userId (tune in)
app.post("/sessions/join-by-id", authenticateHTTP, (req, res) => {
  const { userId: stationUserId } = req.body;
  if (!stationUserId || typeof stationUserId !== "string") {
    return res.status(400).json({ error: "userId required" });
  }

  // Station must exist in DB
  const station = stmtGetStation.get(stationUserId);
  if (!station) {
    return res.status(404).json({ error: "Station not found" });
  }

  // Boot live session if needed
  let live = liveSessions.get(stationUserId);
  if (!live) {
    live = bootLiveSession(station);
  }

  if (live.members.size >= MAX_MEMBERS) {
    return res.status(409).json({ error: "Station is full" });
  }

  console.log(
    `[session:join-by-id] station=${stationUserId} members=${live.members.size}`
  );
  res.json({
    userId: stationUserId,
    djUserId: live.members.has(stationUserId) ? stationUserId : null,
    memberCount: live.members.size,
  });
});

// Get session snapshot (for reconnection)
app.get("/sessions/:userId", authenticateHTTP, (req, res) => {
  const live = liveSessions.get(req.params.userId);
  if (!live) {
    // Check if station exists but is idle
    const station = stmtGetStation.get(req.params.userId);
    if (station) {
      return res.json(idleStationSnapshot(station));
    }
    return res.status(404).json({ error: "Station not found" });
  }

  res.json(liveSessionSnapshot(live));
});

// --- WebSocket Server ---

const server = createServer(app);
const wss = new WebSocketServer({ noServer: true });

server.on("upgrade", (request, socket, head) => {
  const url = new URL(request.url, `http://${request.headers.host}`);
  const token = url.searchParams.get("token");
  // Accept both sessionId (legacy) and userId for station identification
  const stationUserId =
    url.searchParams.get("userId") || url.searchParams.get("sessionId");

  if (!token || !stationUserId) {
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

  // Look up station
  const station = stmtGetStation.get(stationUserId);
  if (!station) {
    socket.write("HTTP/1.1 404 Not Found\r\n\r\n");
    socket.destroy();
    return;
  }

  // Boot live session if needed
  let live = liveSessions.get(stationUserId);
  if (!live) {
    live = bootLiveSession(station);
  }

  wss.handleUpgrade(request, socket, head, (ws) => {
    ws.user = user;
    ws.stationUserId = stationUserId;
    wss.emit("connection", ws, request);
  });
});

wss.on("connection", (ws) => {
  const { stationUserId } = ws;
  const userId = ws.user.sub;
  const displayName = ws.user.name || userId;
  const live = liveSessions.get(stationUserId);

  if (!live) {
    ws.close(4004, "Station not found");
    return;
  }

  if (live.members.size >= MAX_MEMBERS && !live.members.has(userId)) {
    ws.close(4009, "Station full");
    return;
  }

  // Replace existing connection
  const existingMember = live.members.get(userId);
  if (existingMember?.ws?.readyState === 1) {
    existingMember.ws.close(4000, "Replaced by new connection");
  }

  // Cancel teardown if reconnecting
  if (live.destroyTimeout) {
    clearTimeout(live.destroyTimeout);
    live.destroyTimeout = null;
  }

  live.members.set(userId, {
    userId,
    displayName,
    ws,
    alive: true,
    joinedAt: Date.now(),
  });
  live.lastActivity = Date.now();
  console.log(
    `[ws] connected: ${displayName} to station ${stationUserId}, members=${live.members.size}`
  );

  // Send snapshot
  ws.send(
    JSON.stringify({
      type: "stateSync",
      data: liveSessionSnapshot(live),
      epoch: live.epoch,
      seq: live.sequence,
      timestamp: Date.now(),
    })
  );

  // Notify others
  broadcastToSession(
    live,
    {
      type: "memberJoined",
      data: { userId, displayName },
      epoch: live.epoch,
      seq: ++live.sequence,
      timestamp: Date.now(),
    },
    userId
  );

  ws.on("message", (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      return;
    }
    console.log(
      `[ws:msg] ${displayName}: ${msg.type}`,
      msg.data ? JSON.stringify(msg.data).slice(0, 120) : ""
    );
    handleMessage(live, userId, msg);
  });

  ws.on("close", () => {
    const member = live.members.get(userId);
    if (member?.ws === ws) {
      live.members.delete(userId);
      broadcastToSession(live, {
        type: "memberLeft",
        data: { userId },
        epoch: live.epoch,
        seq: ++live.sequence,
        timestamp: Date.now(),
      });

      // DJ rules: if owner left, djUserId becomes null (autonomous)
      // If a non-owner left, no DJ change needed
      if (userId === stationUserId) {
        // Owner disconnected — broadcast stateSync with djUserId: null
        live.epoch++;
        broadcastToSession(live, {
          type: "stateSync",
          data: liveSessionSnapshot(live),
          epoch: live.epoch,
          seq: live.sequence,
          timestamp: Date.now(),
        });
      }

      // Tear down if empty
      if (live.members.size === 0) {
        snapshotAndTeardown(stationUserId);
      }
    }
  });

  ws.on("pong", () => {
    const member = live.members.get(userId);
    if (member) member.alive = true;
  });
});

// --- Message Handling ---

function handleMessage(live, senderId, msg) {
  live.lastActivity = Date.now();
  const isOwner = senderId === live.userId;
  // DJ is the owner when connected, null otherwise
  const isDJ = isOwner && live.members.has(live.userId);

  switch (msg.type) {
    case "playPrepare": {
      if (!isDJ) return;
      if (!msg.data?.trackId) return;

      live.currentTrack = msg.data.track || { id: msg.data.trackId };
      live.epoch++;
      live.sequence++;

      broadcastToSession(live, {
        type: "playPrepare",
        data: msg.data,
        epoch: live.epoch,
        seq: live.sequence,
        timestamp: Date.now(),
      });
      break;
    }

    case "playCommit": {
      if (!isDJ) return;

      live.isPlaying = true;
      live.positionMs = msg.data?.positionMs || 0;
      live.positionTimestamp = msg.data?.ntpTimestamp || Date.now();
      live.sequence++;

      broadcastToSession(live, {
        type: "playCommit",
        data: msg.data,
        epoch: live.epoch,
        seq: live.sequence,
        timestamp: Date.now(),
      });
      scheduleAdvancement(live);
      break;
    }

    case "pause": {
      if (!isDJ) return;

      live.isPlaying = false;
      clearAdvancement(live);
      if (live.positionTimestamp) {
        const elapsed = Date.now() - live.positionTimestamp;
        live.positionMs += elapsed;
        live.positionTimestamp = Date.now();
      }
      live.sequence++;

      broadcastToSession(live, {
        type: "pause",
        data: { positionMs: live.positionMs, ntpTimestamp: Date.now() },
        epoch: live.epoch,
        seq: live.sequence,
        timestamp: Date.now(),
      });
      break;
    }

    case "resume": {
      if (!isDJ) return;

      live.isPlaying = true;
      live.positionTimestamp = Date.now();
      live.sequence++;

      broadcastToSession(live, {
        type: "resume",
        data: {
          positionMs: live.positionMs,
          ntpTimestamp: Date.now(),
          executionTime: msg.data?.executionTime || Date.now() + 1500,
        },
        epoch: live.epoch,
        seq: live.sequence,
        timestamp: Date.now(),
      });
      scheduleAdvancement(live);
      break;
    }

    case "seek": {
      if (!isDJ) return;

      live.positionMs = msg.data?.positionMs || 0;
      live.positionTimestamp = Date.now();
      live.sequence++;

      broadcastToSession(live, {
        type: "seek",
        data: msg.data,
        epoch: live.epoch,
        seq: live.sequence,
        timestamp: Date.now(),
      });
      if (live.isPlaying) scheduleAdvancement(live);
      break;
    }

    case "skip": {
      if (!isDJ) return;
      advanceQueue(live);
      break;
    }

    case "addToQueue": {
      if (!msg.data?.track || !msg.data?.nonce) return;
      if (live.tracks.length >= MAX_QUEUE_SIZE) return;
      if (live.tracks.some((t) => t.nonce === msg.data.nonce)) return;

      const t = msg.data.track;
      const durationMs = Number(t.durationMs);
      if (!Number.isFinite(durationMs) || durationMs <= 0 || durationMs > MAX_TRACK_DURATION_MS) return;

      const queueEntry = {
        id: String(t.id || "").slice(0, 64),
        name: String(t.name || "").slice(0, 256),
        artist: String(t.artist || "").slice(0, 256),
        albumName: String(t.albumName || "").slice(0, 256),
        albumArtURL: String(t.albumArtURL || "").slice(0, 512),
        durationMs,
        nonce: msg.data.nonce,
        addedBy: senderId,
      };
      live.tracks.push(queueEntry);
      persistTracks(live);
      live.sequence++;

      broadcastToSession(live, {
        type: "queueUpdate",
        data: { queue: getUpcomingQueue(live) },
        epoch: live.epoch,
        seq: live.sequence,
        timestamp: Date.now(),
      });
      break;
    }

    case "batchAddToQueue": {
      if (!isDJ) return;
      const { tracks, nonce } = msg.data || {};
      if (!Array.isArray(tracks) || tracks.length === 0) break;
      if (!nonce || typeof nonce !== "string") break;
      if (live.tracks.some((t) => t.nonce === nonce)) break;

      const available = MAX_QUEUE_SIZE - live.tracks.length;
      for (const track of tracks.slice(0, available)) {
        const durationMs = Number(track.durationMs);
        if (!Number.isFinite(durationMs) || durationMs <= 0) continue;
        if (durationMs > MAX_TRACK_DURATION_MS) continue;
        live.tracks.push({
          id: String(track.id || "").slice(0, 64),
          name: String(track.name || "").slice(0, 256),
          artist: String(track.artist || "").slice(0, 256),
          albumName: String(track.albumName || "").slice(0, 256),
          albumArtURL: String(track.albumArtURL || "").slice(0, 512),
          durationMs,
          addedBy: senderId,
          nonce,
        });
      }
      persistTracks(live);
      live.sequence++;

      broadcastToSession(live, {
        type: "queueUpdate",
        data: { queue: getUpcomingQueue(live) },
        epoch: live.epoch,
        seq: live.sequence,
        timestamp: Date.now(),
      });
      break;
    }

    case "removeFromQueue": {
      if (!isDJ) return;
      if (!msg.data?.trackId) return;

      // Find and remove from tracks array (only in upcoming portion)
      const removeIdx = live.tracks.findIndex(
        (t, i) => i > live.trackIndex && t.id === msg.data.trackId
      );
      if (removeIdx !== -1) {
        live.tracks.splice(removeIdx, 1);
        persistTracks(live);
      }
      live.sequence++;

      broadcastToSession(live, {
        type: "queueUpdate",
        data: { queue: getUpcomingQueue(live) },
        epoch: live.epoch,
        seq: live.sequence,
        timestamp: Date.now(),
      });
      break;
    }

    case "driftReport": {
      // Relay to station owner if connected
      const ownerMember = live.members.get(live.userId);
      if (ownerMember?.ws?.readyState === 1) {
        ownerMember.ws.send(
          JSON.stringify({
            type: "driftReport",
            data: { ...msg.data, fromUserId: senderId },
            timestamp: Date.now(),
          })
        );
      }
      break;
    }

    case "ping": {
      const member = live.members.get(senderId);
      if (member?.ws?.readyState === 1) {
        member.ws.send(
          JSON.stringify({
            type: "pong",
            data: {
              clientSendTime: msg.data?.clientSendTime,
              serverTime: Date.now(),
            },
          })
        );
      }
      break;
    }
  }
}

// --- Live Session Management ---

function bootLiveSession(stationRow) {
  const tracks = safeParseTracksJson(stationRow.tracks_json);
  const { trackIndex, positionMs } = computePosition(
    tracks,
    stationRow.snapshot_track_index,
    stationRow.snapshot_elapsed_ms,
    stationRow.snapshot_timestamp
  );

  const currentTrack = tracks[trackIndex] || null;
  const isPlaying = currentTrack !== null && tracks.length > 0;

  const live = {
    userId: stationRow.user_id,
    members: new Map(),
    epoch: 0,
    sequence: 0,
    currentTrack,
    isPlaying,
    positionMs,
    positionTimestamp: Date.now(),
    tracks,
    trackIndex,
    lastActivity: Date.now(),
    advancementTimer: null,
    destroyTimeout: null,
  };

  liveSessions.set(stationRow.user_id, live);

  if (isPlaying) {
    scheduleAdvancement(live);
  }

  console.log(
    `[session:boot] station=${stationRow.user_id} track=${trackIndex}/${tracks.length} pos=${positionMs}ms`
  );
  return live;
}

function snapshotAndTeardown(userId) {
  const live = liveSessions.get(userId);
  if (!live) return;

  // Flush any pending debounced track write
  const pendingWrite = persistDebounceTimers.get(userId);
  if (pendingWrite) {
    clearTimeout(pendingWrite);
    persistDebounceTimers.delete(userId);
  }

  clearAdvancement(live);
  if (live.destroyTimeout) {
    clearTimeout(live.destroyTimeout);
    live.destroyTimeout = null;
  }

  // Compute current elapsed position
  let elapsedMs = live.positionMs;
  if (live.isPlaying && live.positionTimestamp) {
    elapsedMs += Date.now() - live.positionTimestamp;
  }

  // Save snapshot to SQLite
  saveSnapshot(userId, live.tracks, live.trackIndex, elapsedMs);

  liveSessions.delete(userId);
  console.log(
    `[session:teardown] station=${userId} track=${live.trackIndex} elapsed=${elapsedMs}ms`
  );
}

function saveSnapshot(userId, tracks, trackIndex, elapsedMs) {
  stmtSaveSnapshot.run(
    JSON.stringify(tracks),
    trackIndex,
    Math.max(0, Math.round(elapsedMs)),
    Date.now(),
    userId
  );
}

/** @type {Map<string, NodeJS.Timeout>} userId → pending write timer */
const persistDebounceTimers = new Map();

function persistTracks(live) {
  const existing = persistDebounceTimers.get(live.userId);
  if (existing) clearTimeout(existing);

  persistDebounceTimers.set(
    live.userId,
    setTimeout(() => {
      persistDebounceTimers.delete(live.userId);
      stmtUpdateTracks.run(JSON.stringify(live.tracks), live.userId);
    }, 500)
  );
}

// --- Compute Position (Lazy Snapshot) ---

export function computePosition(
  tracks,
  snapshotTrackIndex,
  snapshotElapsedMs,
  snapshotTimestamp
) {
  const len = tracks.length;
  // Check if any tracks have valid durations
  const hasValidTracks = tracks.some((t) => {
    const d = Number(t.durationMs);
    return Number.isFinite(d) && d > 0;
  });
  if (!hasValidTracks) return { trackIndex: 0, positionMs: 0 };
  if (len === 0) return { trackIndex: 0, positionMs: 0 };

  // Clamp snapshot index
  const idx = Math.max(0, Math.min(snapshotTrackIndex ?? 0, len - 1));

  // If no snapshot timestamp, just return the clamped position
  if (!snapshotTimestamp || snapshotTimestamp <= 0) {
    return { trackIndex: idx, positionMs: Math.max(0, snapshotElapsedMs ?? 0) };
  }

  let wallClockElapsed = Date.now() - snapshotTimestamp;
  if (wallClockElapsed <= 0) {
    return { trackIndex: idx, positionMs: Math.max(0, snapshotElapsedMs ?? 0) };
  }

  // Clamp snapshotElapsedMs
  const trackDuration = Number(tracks[idx]?.durationMs) || 0;
  const clampedElapsed = Math.max(
    0,
    Math.min(snapshotElapsedMs ?? 0, trackDuration)
  );

  // Remaining time in snapshot track
  const remainingInCurrent = Math.max(0, trackDuration - clampedElapsed);

  if (wallClockElapsed <= remainingInCurrent) {
    return {
      trackIndex: idx,
      positionMs: clampedElapsed + wallClockElapsed,
    };
  }

  wallClockElapsed -= remainingInCurrent;

  // Calculate total loop duration (sum of all valid track durations)
  let totalLoopMs = 0;
  for (const t of tracks) {
    const d = Number(t.durationMs);
    if (Number.isFinite(d) && d > 0) totalLoopMs += d;
  }

  if (totalLoopMs <= 0) {
    return { trackIndex: idx, positionMs: 0 };
  }

  // Skip full loops with modular arithmetic
  wallClockElapsed = wallClockElapsed % totalLoopMs;

  // Walk forward from next track
  let current = (idx + 1) % len;
  for (let i = 0; i < len; i++) {
    const d = Number(tracks[current]?.durationMs) || 0;
    if (d <= 0) {
      current = (current + 1) % len;
      continue;
    }
    if (wallClockElapsed < d) {
      return { trackIndex: current, positionMs: wallClockElapsed };
    }
    wallClockElapsed -= d;
    current = (current + 1) % len;
  }

  // Shouldn't reach here, but safe fallback
  return { trackIndex: 0, positionMs: 0 };
}

// --- Queue Advancement ---

function scheduleAdvancement(live) {
  clearAdvancement(live);
  if (!live.currentTrack || !live.isPlaying) return;

  const durationMs = Number(live.currentTrack.durationMs);
  if (
    !Number.isFinite(durationMs) ||
    durationMs <= 0 ||
    durationMs > MAX_TRACK_DURATION_MS
  )
    return;

  const elapsed = Date.now() - live.positionTimestamp;
  const currentPositionMs = live.positionMs + elapsed;
  const remainingMs = durationMs - currentPositionMs;

  if (remainingMs <= 0) {
    advanceQueue(live);
    return;
  }

  live.advancementTimer = setTimeout(() => {
    advanceQueue(live);
  }, remainingMs);
}

function clearAdvancement(live) {
  if (live.advancementTimer) {
    clearTimeout(live.advancementTimer);
    live.advancementTimer = null;
  }
}

function advanceQueue(live) {
  if (live.tracks.length === 0) {
    live.isPlaying = false;
    live.currentTrack = null;
    broadcastToSession(live, {
      type: "stateSync",
      data: liveSessionSnapshot(live),
      epoch: live.epoch,
      seq: ++live.sequence,
      timestamp: Date.now(),
    });
    return;
  }

  // Advance cursor with wrapping
  live.trackIndex = (live.trackIndex + 1) % live.tracks.length;
  live.currentTrack = live.tracks[live.trackIndex];
  live.positionMs = 0;
  live.positionTimestamp = Date.now();
  live.isPlaying = true;
  live.epoch++;
  live.sequence = 0;
  live.lastActivity = Date.now();

  broadcastToSession(live, {
    type: "stateSync",
    data: liveSessionSnapshot(live),
    epoch: live.epoch,
    seq: live.sequence,
    timestamp: Date.now(),
  });

  scheduleAdvancement(live);
}

// --- Snapshots ---

function liveSessionSnapshot(live) {
  const djUserId = live.members.has(live.userId) ? live.userId : null;
  return {
    id: live.userId,
    creatorId: live.userId,
    djUserId,
    members: Array.from(live.members.values()).map((m) => ({
      userId: m.userId,
      displayName: m.displayName,
    })),
    epoch: live.epoch,
    sequence: live.sequence,
    currentTrack: live.currentTrack,
    isPlaying: live.isPlaying,
    positionMs: live.positionMs,
    positionTimestamp: live.positionTimestamp,
    queue: getUpcomingQueue(live),
  };
}

function idleStationSnapshot(stationRow) {
  const tracks = safeParseTracksJson(stationRow.tracks_json);
  const idx = Math.min(
    stationRow.snapshot_track_index,
    Math.max(0, tracks.length - 1)
  );
  return {
    id: stationRow.user_id,
    creatorId: stationRow.user_id,
    djUserId: null,
    members: [],
    epoch: 0,
    sequence: 0,
    currentTrack: tracks[idx] || null,
    isPlaying: false,
    positionMs: stationRow.snapshot_elapsed_ms,
    positionTimestamp: stationRow.snapshot_timestamp,
    queue: tracks.length > 1
      ? [...tracks.slice(idx + 1), ...tracks.slice(0, idx)]
      : [],
  };
}

/** Return tracks after the current cursor position */
function getUpcomingQueue(live) {
  if (live.tracks.length === 0) return [];
  // Return all tracks except the current one, in order from next to end then wrap
  const upcoming = [];
  for (let i = 1; i < live.tracks.length; i++) {
    upcoming.push(live.tracks[(live.trackIndex + i) % live.tracks.length]);
  }
  return upcoming;
}

// --- Helpers ---

function broadcastToSession(live, message, excludeUserId = null) {
  const payload = JSON.stringify(message);
  for (const [userId, member] of live.members) {
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
  log.set(key, timestamps.slice(-20));
}

// --- Ping/Pong ---

setInterval(() => {
  const now = Date.now();

  for (const [userId, live] of liveSessions) {
    // Ping all members
    for (const [memberId, member] of live.members) {
      if (!member.alive) {
        member.ws.terminate();
        live.members.delete(memberId);
        broadcastToSession(live, {
          type: "memberLeft",
          data: { userId: memberId },
          epoch: live.epoch,
          seq: ++live.sequence,
          timestamp: now,
        });
        continue;
      }
      member.alive = false;
      member.ws.ping();
    }

    if (live.members.size === 0) {
      snapshotAndTeardown(userId);
    }
  }
}, PING_INTERVAL_MS);

// --- Rate limit cleanup every 5 minutes ---

setInterval(() => {
  const now = Date.now();
  for (const [key, timestamps] of joinAttemptLog) {
    const recent = timestamps.filter((t) => now - t < 60 * 1000);
    if (recent.length === 0) joinAttemptLog.delete(key);
    else joinAttemptLog.set(key, recent);
  }
}, 5 * 60 * 1000);

// --- Shutdown Handler ---

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => {
    console.log(`[shutdown] ${signal} received, snapshotting ${liveSessions.size} sessions`);
    for (const [userId, live] of liveSessions) {
      let elapsedMs = live.positionMs;
      if (live.isPlaying && live.positionTimestamp) {
        elapsedMs += Date.now() - live.positionTimestamp;
      }
      saveSnapshot(userId, live.tracks, live.trackIndex, elapsedMs);
    }
    db.pragma("wal_checkpoint(TRUNCATE)");
    db.close();
    process.exit(0);
  });
}

// --- Start ---

server.listen(PORT, () => {
  console.log(`[PirateRadio] Server listening on port ${PORT}`);
});
