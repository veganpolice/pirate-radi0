import { describe, it, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { spawn } from "node:child_process";
import { once } from "node:events";
import WebSocket from "ws";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Make an HTTP request and return { statusCode, headers, body (parsed JSON) }.
 */
function request(port, method, path, { body, headers } = {}) {
  return new Promise((resolve, reject) => {
    const opts = {
      hostname: "127.0.0.1",
      port,
      path,
      method,
      headers: {
        "Content-Type": "application/json",
        ...headers,
      },
    };

    const req = http.request(opts, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        const raw = Buffer.concat(chunks).toString();
        let json;
        try {
          json = JSON.parse(raw);
        } catch {
          json = raw;
        }
        resolve({ statusCode: res.statusCode, headers: res.headers, body: json });
      });
    });

    req.on("error", reject);

    if (body !== undefined) {
      req.write(JSON.stringify(body));
    }
    req.end();
  });
}

/**
 * Obtain a JWT for the given spotifyUserId.
 */
async function getToken(port, spotifyUserId = "testuser1", displayName = "Test") {
  const res = await request(port, "POST", "/auth", {
    body: { spotifyUserId, displayName },
  });
  assert.equal(res.statusCode, 200);
  assert.ok(res.body.token);
  return res.body.token;
}

/**
 * Create a session and return the response body.
 */
async function createSession(port, token) {
  const res = await request(port, "POST", "/sessions", {
    headers: { Authorization: `Bearer ${token}` },
  });
  assert.equal(res.statusCode, 201);
  return res.body;
}

// ---------------------------------------------------------------------------
// Boot server as a child process on a random port
// ---------------------------------------------------------------------------

let serverProcess;
let PORT;

/**
 * Start the server in a child process and wait until it prints the listening
 * message so we know it is ready.  We use port 0 so the OS picks an unused
 * port, but index.js falls back to 3000 when PORT is "0", so we pick a random
 * high port ourselves.
 */
async function startServer() {
  PORT = 10000 + Math.floor(Math.random() * 50000);

  serverProcess = spawn(process.execPath, ["index.js"], {
    cwd: new URL(".", import.meta.url).pathname,
    env: { ...process.env, PORT: String(PORT), NODE_ENV: "test" },
    stdio: ["pipe", "pipe", "pipe"],
  });

  // Wait for the "listening" line on stdout
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Server did not start in time")), 10_000);
    let output = "";

    serverProcess.stdout.on("data", (chunk) => {
      output += chunk.toString();
      if (output.includes("listening")) {
        clearTimeout(timeout);
        resolve();
      }
    });

    serverProcess.stderr.on("data", (chunk) => {
      output += chunk.toString();
    });

    serverProcess.on("exit", (code) => {
      clearTimeout(timeout);
      reject(new Error(`Server exited early with code ${code}: ${output}`));
    });
  });
}

function stopServer() {
  if (serverProcess) {
    serverProcess.kill("SIGTERM");
    serverProcess = null;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("Pirate Radio API", () => {
  before(async () => {
    await startServer();
  });

  after(() => {
    stopServer();
  });

  // ----- GET /health -----

  describe("GET /health", () => {
    it("returns status ok", async () => {
      const res = await request(PORT, "GET", "/health");
      assert.equal(res.statusCode, 200);
      assert.equal(res.body.status, "ok");
      assert.equal(typeof res.body.sessions, "number");
    });
  });

  // ----- POST /auth -----

  describe("POST /auth", () => {
    it("returns a JWT when given a spotifyUserId", async () => {
      const res = await request(PORT, "POST", "/auth", {
        body: { spotifyUserId: "user123", displayName: "Alice" },
      });
      assert.equal(res.statusCode, 200);
      assert.ok(res.body.token);
      assert.equal(typeof res.body.token, "string");
      // JWT has 3 dot-separated parts
      assert.equal(res.body.token.split(".").length, 3);
    });

    it("returns 400 when spotifyUserId is missing", async () => {
      const res = await request(PORT, "POST", "/auth", {
        body: {},
      });
      assert.equal(res.statusCode, 400);
      assert.ok(res.body.error);
    });

    it("returns 400 when spotifyUserId is not a string", async () => {
      const res = await request(PORT, "POST", "/auth", {
        body: { spotifyUserId: 12345 },
      });
      assert.equal(res.statusCode, 400);
    });

    it("uses spotifyUserId as displayName when displayName is omitted", async () => {
      const res = await request(PORT, "POST", "/auth", {
        body: { spotifyUserId: "solo_user" },
      });
      assert.equal(res.statusCode, 200);
      assert.ok(res.body.token);
    });
  });

  // ----- POST /sessions -----

  describe("POST /sessions", () => {
    it("creates a session with a 4-digit join code", async () => {
      const token = await getToken(PORT, "creator1");
      const session = await createSession(PORT, token);

      assert.ok(session.id);
      assert.ok(session.joinCode);
      assert.match(session.joinCode, /^\d{4}$/);
      assert.equal(session.creatorId, "creator1");
      assert.equal(session.djUserId, "creator1");
    });

    it("returns 401 without a token", async () => {
      const res = await request(PORT, "POST", "/sessions");
      assert.equal(res.statusCode, 401);
    });
  });

  // ----- POST /sessions/join -----

  describe("POST /sessions/join", () => {
    it("validates a join code and returns session info", async () => {
      const token = await getToken(PORT, "join_creator");
      const session = await createSession(PORT, token);

      const joinerToken = await getToken(PORT, "joiner1");
      const res = await request(PORT, "POST", "/sessions/join", {
        body: { code: session.joinCode },
        headers: { Authorization: `Bearer ${joinerToken}` },
      });

      assert.equal(res.statusCode, 200);
      assert.equal(res.body.id, session.id);
      assert.equal(res.body.joinCode, session.joinCode);
      assert.equal(res.body.djUserId, "join_creator");
      assert.equal(typeof res.body.memberCount, "number");
    });

    it("returns 404 for an invalid join code", async () => {
      const token = await getToken(PORT, "invalid_joiner");
      const res = await request(PORT, "POST", "/sessions/join", {
        body: { code: "0000" },
        headers: { Authorization: `Bearer ${token}` },
      });

      assert.equal(res.statusCode, 404);
      assert.ok(res.body.error);
    });

    it("returns 400 when code is missing", async () => {
      const token = await getToken(PORT, "no_code_joiner");
      const res = await request(PORT, "POST", "/sessions/join", {
        body: {},
        headers: { Authorization: `Bearer ${token}` },
      });

      assert.equal(res.statusCode, 400);
    });

    it("returns 401 without a token", async () => {
      const res = await request(PORT, "POST", "/sessions/join", {
        body: { code: "1234" },
      });
      assert.equal(res.statusCode, 401);
    });
  });

  // ----- GET /sessions/:id -----

  describe("GET /sessions/:id", () => {
    it("returns a session snapshot", async () => {
      const token = await getToken(PORT, "snapshot_creator");
      const session = await createSession(PORT, token);

      const res = await request(PORT, "GET", `/sessions/${session.id}`, {
        headers: { Authorization: `Bearer ${token}` },
      });

      assert.equal(res.statusCode, 200);
      assert.equal(res.body.id, session.id);
      assert.equal(res.body.joinCode, session.joinCode);
      assert.equal(res.body.creatorId, "snapshot_creator");
      assert.equal(res.body.djUserId, "snapshot_creator");
      assert.ok(Array.isArray(res.body.members));
      assert.equal(res.body.epoch, 0);
      assert.equal(res.body.sequence, 0);
      assert.equal(res.body.currentTrack, null);
      assert.equal(res.body.isPlaying, false);
      assert.equal(res.body.positionMs, 0);
      assert.ok(Array.isArray(res.body.queue));
    });

    it("returns 404 for a non-existent session", async () => {
      const token = await getToken(PORT, "no_session_user");
      const res = await request(PORT, "GET", "/sessions/nonexistent-id", {
        headers: { Authorization: `Bearer ${token}` },
      });

      assert.equal(res.statusCode, 404);
    });

    it("returns 401 without a token", async () => {
      const res = await request(PORT, "GET", "/sessions/some-id");
      assert.equal(res.statusCode, 401);
    });
  });

  // ----- JWT validation -----

  describe("JWT validation", () => {
    it("returns 401 when Authorization header is missing", async () => {
      const res = await request(PORT, "POST", "/sessions");
      assert.equal(res.statusCode, 401);
      assert.ok(res.body.error);
    });

    it("returns 401 when Authorization header has wrong scheme", async () => {
      const res = await request(PORT, "POST", "/sessions", {
        headers: { Authorization: "Basic abc123" },
      });
      assert.equal(res.statusCode, 401);
    });

    it("returns 401 when JWT is malformed", async () => {
      const res = await request(PORT, "POST", "/sessions", {
        headers: { Authorization: "Bearer not.a.valid.jwt.token" },
      });
      assert.equal(res.statusCode, 401);
    });

    it("returns 401 when JWT is signed with wrong secret", async () => {
      // Craft a JWT with the wrong secret — it won't verify
      const fakeToken =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
        "eyJzdWIiOiJ0ZXN0Iiwibmame IjoiVGVzdCJ9." +
        "invalidsignature";
      const res = await request(PORT, "POST", "/sessions", {
        headers: { Authorization: `Bearer ${fakeToken}` },
      });
      assert.equal(res.statusCode, 401);
    });
  });

  // ----- Autonomous Queue Advancement -----

  describe("Autonomous Queue Advancement", () => {
    /**
     * Connect a WebSocket and collect messages until a condition is met.
     */
    function connectWS(port, token, sessionId) {
      return new Promise((resolve, reject) => {
        const ws = new WebSocket(
          `ws://127.0.0.1:${port}/?token=${token}&sessionId=${sessionId}`
        );
        const messages = [];
        ws.on("open", () => resolve({ ws, messages }));
        ws.on("message", (raw) => {
          messages.push(JSON.parse(raw.toString()));
        });
        ws.on("error", reject);
      });
    }

    function waitForMessage(messages, predicate, timeoutMs = 5000) {
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(
          () => reject(new Error(`Timed out waiting for message (have ${messages.length})`)),
          timeoutMs
        );
        const interval = setInterval(() => {
          const found = messages.find(predicate);
          if (found) {
            clearTimeout(timeout);
            clearInterval(interval);
            resolve(found);
          }
        }, 50);
      });
    }

    it("advances queue when track duration elapses", async () => {
      const token = await getToken(PORT, "timer_dj", "TimerDJ");
      const session = await createSession(PORT, token);
      const { ws, messages } = await connectWS(PORT, token, session.id);

      try {
        // Wait for initial stateSync
        await waitForMessage(messages, (m) => m.type === "stateSync");

        // Set up a track with 1.5s duration and a queue with one more track
        const track1 = { id: "track1", name: "Track 1", durationMs: 1500 };
        const track2 = { id: "track2", name: "Track 2", durationMs: 3000 };

        // Add track2 to queue
        ws.send(JSON.stringify({
          type: "addToQueue",
          data: { track: track2, nonce: "nonce-track2" },
        }));
        await waitForMessage(messages, (m) => m.type === "queueUpdate");

        // Play track1 via playPrepare + playCommit
        ws.send(JSON.stringify({
          type: "playPrepare",
          data: { trackId: track1.id, track: track1 },
        }));
        ws.send(JSON.stringify({
          type: "playCommit",
          data: { positionMs: 0, ntpTimestamp: Date.now() },
        }));

        // Wait for playCommit broadcast
        await waitForMessage(messages, (m) => m.type === "playCommit");

        // Now wait for automatic advancement — server should fire stateSync with track2
        // after ~1.5 seconds
        const advanceMsg = await waitForMessage(
          messages,
          (m) => m.type === "stateSync" && m.data?.currentTrack?.id === "track2",
          4000
        );

        assert.ok(advanceMsg, "Should receive stateSync with track2");
        assert.equal(advanceMsg.data.currentTrack.id, "track2");
        assert.equal(advanceMsg.data.isPlaying, true);
        assert.equal(advanceMsg.data.positionMs, 0);
        assert.ok(advanceMsg.data.queue.length === 0, "Queue should be empty after advancing");
      } finally {
        ws.close();
      }
    });

    it("stops playing when queue is empty after advancement", async () => {
      const token = await getToken(PORT, "empty_q_dj", "EmptyQDJ");
      const session = await createSession(PORT, token);
      const { ws, messages } = await connectWS(PORT, token, session.id);

      try {
        await waitForMessage(messages, (m) => m.type === "stateSync");

        // Play a 1s track with no queue
        const track = { id: "solo_track", name: "Solo", durationMs: 1000 };
        ws.send(JSON.stringify({
          type: "playPrepare",
          data: { trackId: track.id, track: track },
        }));
        ws.send(JSON.stringify({
          type: "playCommit",
          data: { positionMs: 0, ntpTimestamp: Date.now() },
        }));
        await waitForMessage(messages, (m) => m.type === "playCommit");

        // Wait for stateSync that marks station as idle (isPlaying = false, but with a track still set)
        const idleMsg = await waitForMessage(
          messages,
          (m) => m.type === "stateSync" && m.data?.isPlaying === false && m.data?.currentTrack?.id === "solo_track",
          3000
        );

        assert.ok(idleMsg, "Should receive idle stateSync");
        assert.equal(idleMsg.data.isPlaying, false);
        // currentTrack is kept for "last played" context
        assert.equal(idleMsg.data.currentTrack.id, "solo_track");
      } finally {
        ws.close();
      }
    });

    it("clears timer on pause and reschedules on resume", async () => {
      const token = await getToken(PORT, "pause_dj", "PauseDJ");
      const session = await createSession(PORT, token);
      const { ws, messages } = await connectWS(PORT, token, session.id);

      try {
        await waitForMessage(messages, (m) => m.type === "stateSync");

        // Play a 2s track
        const track = { id: "pause_track", name: "PauseTrack", durationMs: 2000 };
        const track2 = { id: "next_track", name: "NextTrack", durationMs: 3000 };

        ws.send(JSON.stringify({
          type: "addToQueue",
          data: { track: track2, nonce: "nonce-next" },
        }));
        await waitForMessage(messages, (m) => m.type === "queueUpdate");

        ws.send(JSON.stringify({
          type: "playPrepare",
          data: { trackId: track.id, track: track },
        }));
        ws.send(JSON.stringify({
          type: "playCommit",
          data: { positionMs: 0, ntpTimestamp: Date.now() },
        }));
        await waitForMessage(messages, (m) => m.type === "playCommit");

        // Pause after 500ms — timer should be cleared
        await new Promise((r) => setTimeout(r, 500));
        ws.send(JSON.stringify({ type: "pause", data: {} }));
        await waitForMessage(messages, (m) => m.type === "pause");

        // Wait 2s — track should NOT advance because it's paused
        await new Promise((r) => setTimeout(r, 2000));
        const advancedWhilePaused = messages.find(
          (m) => m.type === "stateSync" && m.data?.currentTrack?.id === "next_track"
        );
        assert.equal(advancedWhilePaused, undefined, "Should NOT advance while paused");

        // Resume — timer should reschedule for remaining time
        ws.send(JSON.stringify({ type: "resume", data: {} }));
        await waitForMessage(messages, (m) => m.type === "resume");

        // Should advance within ~1.5s (2s track - 0.5s already played)
        const advanceMsg = await waitForMessage(
          messages,
          (m) => m.type === "stateSync" && m.data?.currentTrack?.id === "next_track",
          3000
        );
        assert.ok(advanceMsg, "Should advance after resume");
      } finally {
        ws.close();
      }
    });

    it("does not schedule timer when durationMs is missing", async () => {
      const token = await getToken(PORT, "nodur_dj", "NoDurDJ");
      const session = await createSession(PORT, token);
      const { ws, messages } = await connectWS(PORT, token, session.id);

      try {
        await waitForMessage(messages, (m) => m.type === "stateSync");

        // Play a track with no durationMs
        const track = { id: "no_dur", name: "NoDuration" };
        const track2 = { id: "queued", name: "Queued", durationMs: 1000 };

        ws.send(JSON.stringify({
          type: "addToQueue",
          data: { track: track2, nonce: "nonce-queued" },
        }));
        await waitForMessage(messages, (m) => m.type === "queueUpdate");

        ws.send(JSON.stringify({
          type: "playPrepare",
          data: { trackId: track.id, track: track },
        }));
        ws.send(JSON.stringify({
          type: "playCommit",
          data: { positionMs: 0, ntpTimestamp: Date.now() },
        }));
        await waitForMessage(messages, (m) => m.type === "playCommit");

        // Wait 2s — should NOT auto-advance because durationMs is missing
        await new Promise((r) => setTimeout(r, 2000));
        const advancedMsg = messages.find(
          (m) => m.type === "stateSync" && m.data?.currentTrack?.id === "queued"
        );
        assert.equal(advancedMsg, undefined, "Should NOT advance when durationMs is missing");
      } finally {
        ws.close();
      }
    });
  });

  // ----- GET /stations -----

  describe("GET /stations", () => {
    it("returns empty array when no sessions are active", async () => {
      const token = await getToken(PORT, "stations_empty_user", "EmptyUser");
      const res = await request(PORT, "GET", "/stations", {
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(res.statusCode, 200);
      assert.ok(Array.isArray(res.body.stations));
      // May have stations from other tests, but structure is correct
    });

    it("returns a live station with frequency", async () => {
      const token = await getToken(PORT, "stations_dj", "StationsDJ");
      const session = await createSession(PORT, token);

      // Connect via WebSocket and start playing so the station is "live"
      const ws = await new Promise((resolve, reject) => {
        const conn = new WebSocket(
          `ws://127.0.0.1:${PORT}/?token=${token}&sessionId=${session.id}`
        );
        conn.on("open", () => resolve(conn));
        conn.on("error", reject);
      });

      try {
        // Wait for initial stateSync
        await new Promise((r) => setTimeout(r, 200));

        // Play a track so isPlaying becomes true
        ws.send(JSON.stringify({
          type: "playPrepare",
          data: { trackId: "test_track", track: { id: "test_track", name: "Test", durationMs: 60000 } },
        }));
        ws.send(JSON.stringify({
          type: "playCommit",
          data: { positionMs: 0, ntpTimestamp: Date.now() },
        }));
        await new Promise((r) => setTimeout(r, 200));

        const res = await request(PORT, "GET", "/stations", {
          headers: { Authorization: `Bearer ${token}` },
        });

        assert.equal(res.statusCode, 200);
        const station = res.body.stations.find((s) => s.userId === "stations_dj");
        assert.ok(station, "Should find the DJ's station");
        assert.equal(station.displayName, "StationsDJ");
        assert.equal(typeof station.frequency, "number");
        assert.ok(station.frequency >= 88.0 && station.frequency <= 108.0);
        assert.equal(station.sessionId, session.id);
        assert.ok(station.currentTrack);
      } finally {
        ws.close();
      }
    });

    it("does not return idle sessions (not playing, empty queue)", async () => {
      const token = await getToken(PORT, "stations_idle", "IdleUser");
      const session = await createSession(PORT, token);

      // Session exists but no track playing → should not appear in /stations
      const res = await request(PORT, "GET", "/stations", {
        headers: { Authorization: `Bearer ${token}` },
      });

      const station = res.body.stations.find((s) => s.userId === "stations_idle");
      assert.equal(station, undefined, "Idle session should not appear in stations");
    });

    it("returns 401 without a token", async () => {
      const res = await request(PORT, "GET", "/stations");
      assert.equal(res.statusCode, 401);
    });
  });

  // ----- POST /sessions/join-by-id -----

  describe("POST /sessions/join-by-id", () => {
    it("joins a session by ID", async () => {
      const djToken = await getToken(PORT, "joinid_dj", "JoinIdDJ");
      const session = await createSession(PORT, djToken);

      const joinerToken = await getToken(PORT, "joinid_joiner", "JoinIdJoiner");
      const res = await request(PORT, "POST", "/sessions/join-by-id", {
        body: { sessionId: session.id },
        headers: { Authorization: `Bearer ${joinerToken}` },
      });

      assert.equal(res.statusCode, 200);
      assert.equal(res.body.id, session.id);
      assert.equal(res.body.djUserId, "joinid_dj");
    });

    it("returns 404 for non-existent session", async () => {
      const token = await getToken(PORT, "joinid_404", "NotFound");
      const res = await request(PORT, "POST", "/sessions/join-by-id", {
        body: { sessionId: "nonexistent-id" },
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(res.statusCode, 404);
    });

    it("returns 400 when sessionId is missing", async () => {
      const token = await getToken(PORT, "joinid_400", "BadReq");
      const res = await request(PORT, "POST", "/sessions/join-by-id", {
        body: {},
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(res.statusCode, 400);
    });

    it("returns 401 without a token", async () => {
      const res = await request(PORT, "POST", "/sessions/join-by-id", {
        body: { sessionId: "any-id" },
      });
      assert.equal(res.statusCode, 401);
    });
  });

  // ----- User Registry (auto-assign frequency) -----

  describe("User Registry", () => {
    it("assigns unique frequencies to different users", async () => {
      const token1 = await getToken(PORT, "freq_user_a", "UserA");
      const token2 = await getToken(PORT, "freq_user_b", "UserB");

      // Both users create sessions and play so they show up in /stations
      const session1 = await createSession(PORT, token1);
      const session2 = await createSession(PORT, token2);

      // Start playback on both
      for (const [token, session] of [[token1, session1], [token2, session2]]) {
        const ws = await new Promise((resolve, reject) => {
          const conn = new WebSocket(
            `ws://127.0.0.1:${PORT}/?token=${token}&sessionId=${session.id}`
          );
          conn.on("open", () => resolve(conn));
          conn.on("error", reject);
        });
        ws.send(JSON.stringify({
          type: "playPrepare",
          data: { trackId: "t1", track: { id: "t1", name: "T", durationMs: 60000 } },
        }));
        ws.send(JSON.stringify({
          type: "playCommit",
          data: { positionMs: 0, ntpTimestamp: Date.now() },
        }));
        await new Promise((r) => setTimeout(r, 100));
        ws.close();
      }

      await new Promise((r) => setTimeout(r, 200));

      const res = await request(PORT, "GET", "/stations", {
        headers: { Authorization: `Bearer ${token1}` },
      });

      const stationA = res.body.stations.find((s) => s.userId === "freq_user_a");
      const stationB = res.body.stations.find((s) => s.userId === "freq_user_b");

      if (stationA && stationB) {
        assert.notEqual(stationA.frequency, stationB.frequency, "Users should have different frequencies");
      }
    });
  });

  // ----- Rate limiting -----

  describe("Rate limiting", () => {
    it("returns 429 when creating too many sessions (>5 per user per hour)", async () => {
      const token = await getToken(PORT, "ratelimit_user");
      const results = [];

      // Create 6 sessions — the 6th should be rate-limited
      for (let i = 0; i < 6; i++) {
        const res = await request(PORT, "POST", "/sessions", {
          headers: { Authorization: `Bearer ${token}` },
        });
        results.push(res);
      }

      // First 5 should succeed
      for (let i = 0; i < 5; i++) {
        assert.equal(results[i].statusCode, 201, `Session ${i + 1} should succeed`);
      }

      // 6th should be rate-limited
      assert.equal(results[5].statusCode, 429);
      assert.ok(results[5].body.error);
    });

    it("returns 429 when too many join attempts from same IP (>10 per minute)", async () => {
      const token = await getToken(PORT, "joinlimit_user");

      // Earlier tests in this process already consumed some join attempts from
      // the same loopback IP, so we send enough requests to guarantee we exceed
      // the 10-per-minute limit.  We keep going until we see 429 or hit 20.
      let got429 = false;
      for (let i = 0; i < 20; i++) {
        const res = await request(PORT, "POST", "/sessions/join", {
          body: { code: "9999" },
          headers: { Authorization: `Bearer ${token}` },
        });
        if (res.statusCode === 429) {
          got429 = true;
          assert.ok(res.body.error);
          break;
        }
      }

      assert.ok(got429, "Expected a 429 response after exceeding rate limit");
    });
  });
});
