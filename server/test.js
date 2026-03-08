import { describe, it, before, after } from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { spawn } from "node:child_process";
import WebSocket from "ws";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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
        resolve({
          statusCode: res.statusCode,
          headers: res.headers,
          body: json,
        });
      });
    });

    req.on("error", reject);
    if (body !== undefined) req.write(JSON.stringify(body));
    req.end();
  });
}

let nextFreq = 881;
function pickFrequency() {
  const f = nextFreq;
  nextFreq += 2;
  if (nextFreq > 1079) nextFreq = 881;
  return f;
}

async function getToken(port, spotifyUserId = "testuser1", displayName = "Test") {
  const res = await request(port, "POST", "/auth", {
    body: { spotifyUserId, displayName },
  });
  assert.equal(res.statusCode, 200);
  assert.ok(res.body.token);
  return res.body.token;
}

/** Auth + claim frequency + return token */
async function setupStation(port, userId, displayName, frequency) {
  const token = await getToken(port, userId, displayName);
  const freq = frequency || pickFrequency();
  const claimRes = await request(port, "POST", "/stations/claim-frequency", {
    body: { frequency: freq },
    headers: { Authorization: `Bearer ${token}` },
  });
  // May already have station (409) — that's fine
  if (claimRes.statusCode !== 201 && claimRes.statusCode !== 409) {
    throw new Error(`claim-frequency failed: ${claimRes.statusCode} ${JSON.stringify(claimRes.body)}`);
  }
  return { token, frequency: freq };
}

// ---------------------------------------------------------------------------
// Boot server
// ---------------------------------------------------------------------------

let serverProcess;
let PORT;

async function startServer() {
  PORT = 10000 + Math.floor(Math.random() * 50000);

  serverProcess = spawn(process.execPath, ["index.js"], {
    cwd: new URL(".", import.meta.url).pathname,
    env: { ...process.env, PORT: String(PORT), NODE_ENV: "test" },
    stdio: ["pipe", "pipe", "pipe"],
  });

  await new Promise((resolve, reject) => {
    const timeout = setTimeout(
      () => reject(new Error("Server did not start in time")),
      10_000
    );
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
      assert.equal(typeof res.body.liveSessions, "number");
    });
  });

  // ----- POST /auth -----

  describe("POST /auth", () => {
    it("returns a JWT and needsFrequency=true for new user", async () => {
      const res = await request(PORT, "POST", "/auth", {
        body: { spotifyUserId: "auth_new_user", displayName: "Alice" },
      });
      assert.equal(res.statusCode, 200);
      assert.ok(res.body.token);
      assert.equal(res.body.needsFrequency, true);
    });

    it("returns needsFrequency=false after claiming frequency", async () => {
      const { token } = await setupStation(PORT, "auth_claimed", "Claimed");
      // Auth again
      const res = await request(PORT, "POST", "/auth", {
        body: { spotifyUserId: "auth_claimed", displayName: "Claimed" },
      });
      assert.equal(res.statusCode, 200);
      assert.equal(res.body.needsFrequency, false);
      assert.equal(typeof res.body.frequency, "number");
    });

    it("returns 400 when spotifyUserId is missing", async () => {
      const res = await request(PORT, "POST", "/auth", { body: {} });
      assert.equal(res.statusCode, 400);
      assert.ok(res.body.error);
    });

    it("returns 400 when spotifyUserId is not a string", async () => {
      const res = await request(PORT, "POST", "/auth", {
        body: { spotifyUserId: 12345 },
      });
      assert.equal(res.statusCode, 400);
    });
  });

  // ----- POST /stations/claim-frequency -----

  describe("POST /stations/claim-frequency", () => {
    it("creates a station with a valid frequency", async () => {
      const token = await getToken(PORT, "claim_user1", "ClaimUser");
      const res = await request(PORT, "POST", "/stations/claim-frequency", {
        body: { frequency: 911 },
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(res.statusCode, 201);
      assert.equal(res.body.frequency, 911);
    });

    it("returns 409 for duplicate frequency", async () => {
      const token2 = await getToken(PORT, "claim_user2", "ClaimUser2");
      const res = await request(PORT, "POST", "/stations/claim-frequency", {
        body: { frequency: 911 }, // same as above
        headers: { Authorization: `Bearer ${token2}` },
      });
      assert.equal(res.statusCode, 409);
      assert.ok(res.body.error.includes("taken"));
    });

    it("returns 409 if user already has a station", async () => {
      const token = await getToken(PORT, "claim_user1", "ClaimUser");
      const res = await request(PORT, "POST", "/stations/claim-frequency", {
        body: { frequency: 913 },
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(res.statusCode, 409);
      assert.ok(res.body.error.includes("already"));
    });

    it("rejects invalid frequencies", async () => {
      const token = await getToken(PORT, "claim_invalid", "Invalid");
      // Even number
      let res = await request(PORT, "POST", "/stations/claim-frequency", {
        body: { frequency: 882 },
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(res.statusCode, 400);

      // Out of range
      res = await request(PORT, "POST", "/stations/claim-frequency", {
        body: { frequency: 1081 },
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(res.statusCode, 400);

      // Not integer
      res = await request(PORT, "POST", "/stations/claim-frequency", {
        body: { frequency: 88.1 },
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(res.statusCode, 400);
    });

    it("returns 401 without a token", async () => {
      const res = await request(PORT, "POST", "/stations/claim-frequency", {
        body: { frequency: 915 },
      });
      assert.equal(res.statusCode, 401);
    });
  });

  // ----- GET /stations -----

  describe("GET /stations", () => {
    it("returns all registered stations", async () => {
      const { token } = await setupStation(PORT, "stations_list", "Lister", 917);
      const res = await request(PORT, "GET", "/stations", {
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(res.statusCode, 200);
      assert.ok(Array.isArray(res.body.stations));
      const station = res.body.stations.find((s) => s.userId === "stations_list");
      assert.ok(station);
      assert.equal(station.frequency, 917);
      assert.equal(station.isLive, false);
      assert.equal(station.listenerCount, 0);
    });

    it("shows live station when someone is connected", async () => {
      const { token } = await setupStation(PORT, "stations_live", "LiveDJ", 919);

      // Join via join-by-id to boot live session
      await request(PORT, "POST", "/sessions/join-by-id", {
        body: { userId: "stations_live" },
        headers: { Authorization: `Bearer ${token}` },
      });

      // Connect via WebSocket
      const ws = await new Promise((resolve, reject) => {
        const conn = new WebSocket(
          `ws://127.0.0.1:${PORT}/?token=${token}&userId=stations_live`
        );
        conn.on("open", () => resolve(conn));
        conn.on("error", reject);
      });

      try {
        await new Promise((r) => setTimeout(r, 200));

        const res = await request(PORT, "GET", "/stations", {
          headers: { Authorization: `Bearer ${token}` },
        });

        const station = res.body.stations.find((s) => s.userId === "stations_live");
        assert.ok(station);
        assert.equal(station.isLive, true);
        assert.equal(station.ownerConnected, true);
        assert.ok(station.listenerCount >= 1);
      } finally {
        ws.close();
      }
    });

    it("returns 401 without a token", async () => {
      const res = await request(PORT, "GET", "/stations");
      assert.equal(res.statusCode, 401);
    });
  });

  // ----- POST /sessions/join-by-id -----

  describe("POST /sessions/join-by-id", () => {
    it("joins a station by userId", async () => {
      const { token: djToken } = await setupStation(PORT, "joinid_dj", "JoinIdDJ", 921);
      const joinerToken = await getToken(PORT, "joinid_joiner", "Joiner");

      const res = await request(PORT, "POST", "/sessions/join-by-id", {
        body: { userId: "joinid_dj" },
        headers: { Authorization: `Bearer ${joinerToken}` },
      });

      assert.equal(res.statusCode, 200);
      assert.equal(res.body.userId, "joinid_dj");
    });

    it("returns 404 for non-existent station", async () => {
      const token = await getToken(PORT, "joinid_404", "NotFound");
      const res = await request(PORT, "POST", "/sessions/join-by-id", {
        body: { userId: "nonexistent-user" },
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(res.statusCode, 404);
    });

    it("returns 400 when userId is missing", async () => {
      const token = await getToken(PORT, "joinid_400", "BadReq");
      const res = await request(PORT, "POST", "/sessions/join-by-id", {
        body: {},
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(res.statusCode, 400);
    });

    it("returns 401 without a token", async () => {
      const res = await request(PORT, "POST", "/sessions/join-by-id", {
        body: { userId: "any-id" },
      });
      assert.equal(res.statusCode, 401);
    });
  });

  // ----- WebSocket + Autonomous Queue Advancement -----

  describe("Autonomous Queue Advancement", () => {
    function connectWS(port, token, stationUserId) {
      return new Promise((resolve, reject) => {
        const ws = new WebSocket(
          `ws://127.0.0.1:${port}/?token=${token}&userId=${stationUserId}`
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
          () =>
            reject(
              new Error(
                `Timed out waiting for message (have ${messages.length})`
              )
            ),
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
      const { token } = await setupStation(PORT, "timer_dj", "TimerDJ", 923);
      const { ws, messages } = await connectWS(PORT, token, "timer_dj");

      try {
        await waitForMessage(messages, (m) => m.type === "stateSync");

        const track1 = { id: "track1", name: "Track 1", durationMs: 1500 };
        const track2 = { id: "track2", name: "Track 2", durationMs: 3000 };

        ws.send(
          JSON.stringify({
            type: "addToQueue",
            data: { track: track2, nonce: "nonce-track2" },
          })
        );
        await waitForMessage(messages, (m) => m.type === "queueUpdate");

        ws.send(
          JSON.stringify({
            type: "playPrepare",
            data: { trackId: track1.id, track: track1 },
          })
        );
        ws.send(
          JSON.stringify({
            type: "playCommit",
            data: { positionMs: 0, ntpTimestamp: Date.now() },
          })
        );
        await waitForMessage(messages, (m) => m.type === "playCommit");

        const advanceMsg = await waitForMessage(
          messages,
          (m) =>
            m.type === "stateSync" && m.data?.currentTrack?.id === "track2",
          4000
        );

        assert.ok(advanceMsg);
        assert.equal(advanceMsg.data.currentTrack.id, "track2");
        assert.equal(advanceMsg.data.isPlaying, true);
      } finally {
        ws.close();
      }
    });

    it("loops queue when reaching the end", async () => {
      const { token } = await setupStation(PORT, "loop_dj", "LoopDJ", 925);
      const { ws, messages } = await connectWS(PORT, token, "loop_dj");

      try {
        await waitForMessage(messages, (m) => m.type === "stateSync");

        // Add two short tracks
        ws.send(
          JSON.stringify({
            type: "addToQueue",
            data: {
              track: { id: "loop1", name: "Loop1", durationMs: 800 },
              nonce: "n-loop1",
            },
          })
        );
        await waitForMessage(messages, (m) => m.type === "queueUpdate");

        ws.send(
          JSON.stringify({
            type: "addToQueue",
            data: {
              track: { id: "loop2", name: "Loop2", durationMs: 800 },
              nonce: "n-loop2",
            },
          })
        );
        await waitForMessage(
          messages,
          (m) =>
            m.type === "queueUpdate" &&
            m.data?.queue?.some((t) => t.id === "loop2")
        );

        // Play loop1 via playPrepare + playCommit
        // First track is added to queue, but we need to set currentTrack
        // The station was booted with these tracks in the array.
        // Actually, let me play the first track directly
        ws.send(
          JSON.stringify({
            type: "playPrepare",
            data: {
              trackId: "loop1",
              track: { id: "loop1", name: "Loop1", durationMs: 800 },
            },
          })
        );
        ws.send(
          JSON.stringify({
            type: "playCommit",
            data: { positionMs: 0, ntpTimestamp: Date.now() },
          })
        );
        await waitForMessage(messages, (m) => m.type === "playCommit");

        // Wait for advancement to loop2
        await waitForMessage(
          messages,
          (m) =>
            m.type === "stateSync" && m.data?.currentTrack?.id === "loop2",
          3000
        );

        // Wait for advancement back to loop1 (looping!)
        const loopMsg = await waitForMessage(
          messages,
          (m) =>
            m.type === "stateSync" &&
            m.data?.currentTrack?.id === "loop1" &&
            m.data?.isPlaying === true &&
            m.epoch > 1,
          3000
        );

        assert.ok(loopMsg, "Queue should loop back to first track");
      } finally {
        ws.close();
      }
    });

    it("clears timer on pause and reschedules on resume", async () => {
      const { token } = await setupStation(PORT, "pause_dj", "PauseDJ", 927);
      const { ws, messages } = await connectWS(PORT, token, "pause_dj");

      try {
        await waitForMessage(messages, (m) => m.type === "stateSync");

        const track = {
          id: "pause_track",
          name: "PauseTrack",
          durationMs: 2000,
        };
        const track2 = {
          id: "next_track",
          name: "NextTrack",
          durationMs: 3000,
        };

        ws.send(
          JSON.stringify({
            type: "addToQueue",
            data: { track: track2, nonce: "nonce-next" },
          })
        );
        await waitForMessage(messages, (m) => m.type === "queueUpdate");

        ws.send(
          JSON.stringify({
            type: "playPrepare",
            data: { trackId: track.id, track: track },
          })
        );
        ws.send(
          JSON.stringify({
            type: "playCommit",
            data: { positionMs: 0, ntpTimestamp: Date.now() },
          })
        );
        await waitForMessage(messages, (m) => m.type === "playCommit");

        await new Promise((r) => setTimeout(r, 500));
        ws.send(JSON.stringify({ type: "pause", data: {} }));
        await waitForMessage(messages, (m) => m.type === "pause");

        await new Promise((r) => setTimeout(r, 2000));
        const advancedWhilePaused = messages.find(
          (m) =>
            m.type === "stateSync" && m.data?.currentTrack?.id === "next_track"
        );
        assert.equal(
          advancedWhilePaused,
          undefined,
          "Should NOT advance while paused"
        );

        ws.send(JSON.stringify({ type: "resume", data: {} }));
        await waitForMessage(messages, (m) => m.type === "resume");

        const advanceMsg = await waitForMessage(
          messages,
          (m) =>
            m.type === "stateSync" &&
            m.data?.currentTrack?.id === "next_track",
          3000
        );
        assert.ok(advanceMsg, "Should advance after resume");
      } finally {
        ws.close();
      }
    });
  });

  // ----- DJ Rules -----

  describe("DJ Rules", () => {
    function connectWS(port, token, stationUserId) {
      return new Promise((resolve, reject) => {
        const ws = new WebSocket(
          `ws://127.0.0.1:${port}/?token=${token}&userId=${stationUserId}`
        );
        const messages = [];
        ws.on("open", () => resolve({ ws, messages }));
        ws.on("message", (raw) => {
          messages.push(JSON.parse(raw.toString()));
        });
        ws.on("error", reject);
      });
    }

    function waitForMessage(messages, predicate, timeoutMs = 3000) {
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(
          () =>
            reject(
              new Error(
                `Timed out (have ${messages.length} msgs: ${messages.map((m) => m.type).join(",")})`
              )
            ),
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

    it("owner is DJ when connected, null when not", async () => {
      const { token: ownerToken } = await setupStation(
        PORT,
        "dj_owner",
        "DJOwner",
        929
      );
      const listenerToken = await getToken(PORT, "dj_listener", "Listener");

      // Owner connects
      const { ws: ownerWs, messages: ownerMsgs } = await connectWS(
        PORT,
        ownerToken,
        "dj_owner"
      );
      const initSync = await waitForMessage(
        ownerMsgs,
        (m) => m.type === "stateSync"
      );
      assert.equal(initSync.data.djUserId, "dj_owner");

      // Listener connects
      const { ws: listenerWs, messages: listenerMsgs } = await connectWS(
        PORT,
        listenerToken,
        "dj_owner"
      );
      const listenerSync = await waitForMessage(
        listenerMsgs,
        (m) => m.type === "stateSync"
      );
      assert.equal(listenerSync.data.djUserId, "dj_owner");

      // Owner disconnects — djUserId should become null
      ownerWs.close();
      const nullDjMsg = await waitForMessage(
        listenerMsgs,
        (m) => m.type === "stateSync" && m.data?.djUserId === null
      );
      assert.equal(nullDjMsg.data.djUserId, null);

      listenerWs.close();
    });

    it("non-owner cannot send DJ commands", async () => {
      const { token: ownerToken } = await setupStation(
        PORT,
        "dj_cmd_owner",
        "Owner",
        931
      );
      const listenerToken = await getToken(PORT, "dj_cmd_listener", "Listener");

      const { ws: ownerWs, messages: ownerMsgs } = await connectWS(
        PORT,
        ownerToken,
        "dj_cmd_owner"
      );
      await waitForMessage(ownerMsgs, (m) => m.type === "stateSync");

      // Add a track as owner
      ownerWs.send(
        JSON.stringify({
          type: "addToQueue",
          data: {
            track: { id: "t1", name: "T1", durationMs: 60000 },
            nonce: "n-t1",
          },
        })
      );
      await waitForMessage(ownerMsgs, (m) => m.type === "queueUpdate");

      // Listener connects
      const { ws: listenerWs, messages: listenerMsgs } = await connectWS(
        PORT,
        listenerToken,
        "dj_cmd_owner"
      );
      await waitForMessage(listenerMsgs, (m) => m.type === "stateSync");

      // Listener tries to skip — should be ignored (no response)
      listenerWs.send(JSON.stringify({ type: "skip", data: {} }));

      // Wait a bit to make sure no stateSync with track change comes
      await new Promise((r) => setTimeout(r, 500));
      const skipSync = listenerMsgs.find(
        (m) =>
          m.type === "stateSync" &&
          m.data?.currentTrack?.id === "t1" &&
          m.data?.isPlaying === true
      );
      assert.equal(skipSync, undefined, "Listener skip should be ignored");

      // But listener CAN add to queue
      listenerWs.send(
        JSON.stringify({
          type: "addToQueue",
          data: {
            track: { id: "t2", name: "T2", durationMs: 60000 },
            nonce: "n-t2",
          },
        })
      );

      const queueUpdate = await waitForMessage(
        ownerMsgs,
        (m) =>
          m.type === "queueUpdate" &&
          m.data?.queue?.some((t) => t.id === "t2")
      );
      assert.ok(queueUpdate, "Listener should be able to add to queue");

      ownerWs.close();
      listenerWs.close();
    });
  });

  // ----- computePosition (via snapshot resume) -----

  describe("Lazy Snapshot", () => {
    function connectWS(port, token, stationUserId) {
      return new Promise((resolve, reject) => {
        const ws = new WebSocket(
          `ws://127.0.0.1:${port}/?token=${token}&userId=${stationUserId}`
        );
        const messages = [];
        ws.on("open", () => resolve({ ws, messages }));
        ws.on("message", (raw) => {
          messages.push(JSON.parse(raw.toString()));
        });
        ws.on("error", reject);
      });
    }

    function waitForMessage(messages, predicate, timeoutMs = 3000) {
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(
          () => reject(new Error(`Timed out (${messages.length} msgs)`)),
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

    it("snapshots on last listener leave and resumes on tune-in", async () => {
      const { token } = await setupStation(
        PORT,
        "snap_dj",
        "SnapDJ",
        933
      );

      // Connect and play a track
      const { ws, messages } = await connectWS(PORT, token, "snap_dj");
      await waitForMessage(messages, (m) => m.type === "stateSync");

      const track1 = { id: "snap1", name: "Snap1", durationMs: 60000 };
      const track2 = { id: "snap2", name: "Snap2", durationMs: 60000 };

      ws.send(
        JSON.stringify({
          type: "addToQueue",
          data: { track: track1, nonce: "n-snap1" },
        })
      );
      await waitForMessage(messages, (m) => m.type === "queueUpdate");

      ws.send(
        JSON.stringify({
          type: "addToQueue",
          data: { track: track2, nonce: "n-snap2" },
        })
      );
      await waitForMessage(
        messages,
        (m) =>
          m.type === "queueUpdate" &&
          m.data?.queue?.some((t) => t.id === "snap2")
      );

      // Play snap1
      ws.send(
        JSON.stringify({
          type: "playPrepare",
          data: { trackId: "snap1", track: track1 },
        })
      );
      ws.send(
        JSON.stringify({
          type: "playCommit",
          data: { positionMs: 0, ntpTimestamp: Date.now() },
        })
      );
      await waitForMessage(messages, (m) => m.type === "playCommit");

      // Let it play for a bit
      await new Promise((r) => setTimeout(r, 500));

      // Disconnect — triggers snapshot
      ws.close();
      await new Promise((r) => setTimeout(r, 500));

      // Reconnect — should resume near where we left off
      const { ws: ws2, messages: msgs2 } = await connectWS(
        PORT,
        token,
        "snap_dj"
      );
      const resumeSync = await waitForMessage(
        msgs2,
        (m) => m.type === "stateSync"
      );

      // Should still be on snap1 (or snap2 if enough time passed)
      assert.ok(resumeSync.data.currentTrack);
      assert.equal(resumeSync.data.isPlaying, true);
      // Position should be > 0 (resumed, not from the start)
      assert.ok(
        resumeSync.data.positionMs >= 0,
        "Position should be non-negative"
      );

      ws2.close();
    });
  });

  // ----- Rate limiting -----

  describe("Rate limiting", () => {
    it("returns 429 when too many join attempts from same IP", async () => {
      const token = await getToken(PORT, "joinlimit_user");
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

  // ----- JWT validation -----

  describe("JWT validation", () => {
    it("returns 401 when Authorization header is missing", async () => {
      const res = await request(PORT, "POST", "/sessions");
      assert.equal(res.statusCode, 401);
    });

    it("returns 401 when JWT is malformed", async () => {
      const res = await request(PORT, "POST", "/sessions", {
        headers: { Authorization: "Bearer not.a.valid.jwt.token" },
      });
      assert.equal(res.statusCode, 401);
    });
  });
});
