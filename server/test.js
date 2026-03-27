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
        resolve({ statusCode: res.statusCode, headers: res.headers, body: json });
      });
    });

    req.on("error", reject);
    if (body !== undefined) req.write(JSON.stringify(body));
    req.end();
  });
}

async function getToken(port, spotifyUserId = "testuser1", displayName = "Test") {
  const res = await request(port, "POST", "/auth", {
    body: { spotifyUserId, displayName },
  });
  assert.equal(res.statusCode, 200);
  assert.ok(res.body.token);
  return res.body.token;
}

// ---------------------------------------------------------------------------
// Boot server as a child process
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
// WebSocket helpers
// ---------------------------------------------------------------------------

function connectWS(port, token, stationId) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(
      `ws://127.0.0.1:${port}/?token=${token}&sessionId=${stationId}`
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("Pirate Radio — Public Stations", () => {
  before(async () => {
    await startServer();
  });

  after(() => {
    stopServer();
  });

  // ----- GET /health -----

  describe("GET /health", () => {
    it("returns status ok with station count", async () => {
      const res = await request(PORT, "GET", "/health");
      assert.equal(res.statusCode, 200);
      assert.equal(res.body.status, "ok");
      assert.equal(res.body.stations, 5);
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
      assert.equal(res.body.token.split(".").length, 3);
    });

    it("returns 400 when spotifyUserId is missing", async () => {
      const res = await request(PORT, "POST", "/auth", { body: {} });
      assert.equal(res.statusCode, 400);
    });

    it("returns 400 when spotifyUserId is not a string", async () => {
      const res = await request(PORT, "POST", "/auth", {
        body: { spotifyUserId: 12345 },
      });
      assert.equal(res.statusCode, 400);
    });
  });

  // ----- GET /stations -----

  describe("GET /stations", () => {
    it("always returns all 5 stations", async () => {
      const token = await getToken(PORT, "stations_user");
      const res = await request(PORT, "GET", "/stations", {
        headers: { Authorization: `Bearer ${token}` },
      });

      assert.equal(res.statusCode, 200);
      assert.equal(res.body.stations.length, 5);

      const names = res.body.stations.map((s) => s.name);
      assert.ok(names.includes("88.🏴‍☠️"));
      assert.ok(names.includes("93.🔥"));
      assert.ok(names.includes("97.🌊"));
      assert.ok(names.includes("101.💀"));
      assert.ok(names.includes("107.👑"));
    });

    it("includes station metadata", async () => {
      const token = await getToken(PORT, "meta_user");
      const res = await request(PORT, "GET", "/stations", {
        headers: { Authorization: `Bearer ${token}` },
      });

      const station = res.body.stations[0];
      assert.ok(station.id);
      assert.ok(station.name);
      assert.equal(typeof station.frequency, "number");
      assert.equal(typeof station.listenerCount, "number");
      assert.equal(typeof station.queueLength, "number");
      assert.equal(typeof station.isPlaying, "boolean");
    });

    it("returns 401 without a token", async () => {
      const res = await request(PORT, "GET", "/stations");
      assert.equal(res.statusCode, 401);
    });
  });

  // ----- GET /stations/:id -----

  describe("GET /stations/:id", () => {
    it("returns a station snapshot", async () => {
      const token = await getToken(PORT, "snapshot_user");
      const res = await request(PORT, "GET", "/stations/station-88", {
        headers: { Authorization: `Bearer ${token}` },
      });

      assert.equal(res.statusCode, 200);
      assert.equal(res.body.id, "station-88");
      assert.equal(res.body.name, "88.🏴‍☠️");
      assert.equal(res.body.frequency, 88.1);
      assert.ok(Array.isArray(res.body.members));
      assert.ok(Array.isArray(res.body.queue));
      assert.equal(typeof res.body.epoch, "number");
      assert.equal(typeof res.body.isPlaying, "boolean");
    });

    it("returns 404 for non-existent station", async () => {
      const token = await getToken(PORT, "no_station_user");
      const res = await request(PORT, "GET", "/stations/station-nonexistent", {
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(res.statusCode, 404);
    });

    it("returns 401 without a token", async () => {
      const res = await request(PORT, "GET", "/stations/station-88");
      assert.equal(res.statusCode, 401);
    });
  });

  // ----- JWT validation -----

  describe("JWT validation", () => {
    it("returns 401 when Authorization header is missing", async () => {
      const res = await request(PORT, "GET", "/stations");
      assert.equal(res.statusCode, 401);
    });

    it("returns 401 when Authorization header has wrong scheme", async () => {
      const res = await request(PORT, "GET", "/stations", {
        headers: { Authorization: "Basic abc123" },
      });
      assert.equal(res.statusCode, 401);
    });

    it("returns 401 when JWT is malformed", async () => {
      const res = await request(PORT, "GET", "/stations", {
        headers: { Authorization: "Bearer not.a.valid.jwt.token" },
      });
      assert.equal(res.statusCode, 401);
    });
  });

  // ----- WebSocket Connection -----

  describe("WebSocket Connection", () => {
    it("connects to a station and receives stateSync", async () => {
      const token = await getToken(PORT, "ws_user", "WSUser");
      const { ws, messages } = await connectWS(PORT, token, "station-93");

      try {
        const sync = await waitForMessage(messages, (m) => m.type === "stateSync");
        assert.equal(sync.data.id, "station-93");
        assert.equal(sync.data.name, "93.🔥");
        assert.ok(Array.isArray(sync.data.members));
      } finally {
        ws.close();
      }
    });

    it("notifies others when a member joins", async () => {
      const token1 = await getToken(PORT, "join_user1", "User1");
      const token2 = await getToken(PORT, "join_user2", "User2");

      const { ws: ws1, messages: msgs1 } = await connectWS(PORT, token1, "station-97");
      await waitForMessage(msgs1, (m) => m.type === "stateSync");

      const { ws: ws2 } = await connectWS(PORT, token2, "station-97");

      try {
        const joinMsg = await waitForMessage(msgs1, (m) => m.type === "memberJoined");
        assert.equal(joinMsg.data.userId, "join_user2");
        assert.equal(joinMsg.data.displayName, "User2");
      } finally {
        ws1.close();
        ws2.close();
      }
    });

    it("replaces old WebSocket when member reconnects", async () => {
      const token = await getToken(PORT, "recon_user", "ReconUser");
      const { ws: ws1, messages: msgs1 } = await connectWS(PORT, token, "station-88");
      await waitForMessage(msgs1, (m) => m.type === "stateSync");

      const { ws: ws2, messages: msgs2 } = await connectWS(PORT, token, "station-88");
      await waitForMessage(msgs2, (m) => m.type === "stateSync");

      await new Promise((resolve) => {
        ws1.on("close", resolve);
        setTimeout(resolve, 2000);
      });

      assert.equal(ws1.readyState, WebSocket.CLOSED);
      assert.equal(ws2.readyState, WebSocket.OPEN);
      ws2.close();
    });
  });

  // ----- Anyone Can Skip -----

  describe("Skip (open to all)", () => {
    it("any user can skip the current track", async () => {
      const token = await getToken(PORT, "skip_user", "SkipUser");
      const { ws, messages } = await connectWS(PORT, token, "station-107");

      try {
        await waitForMessage(messages, (m) => m.type === "stateSync");

        // Add two tracks
        ws.send(JSON.stringify({
          type: "addToQueue",
          data: { track: { id: "skip1", name: "Skip 1", durationMs: 60000 }, nonce: "skip-n1" },
        }));
        await waitForMessage(messages, (m) => m.type === "queueUpdate");

        ws.send(JSON.stringify({
          type: "addToQueue",
          data: { track: { id: "skip2", name: "Skip 2", durationMs: 60000 }, nonce: "skip-n2" },
        }));

        // Wait for auto-start (first addToQueue triggers playback)
        const autoStart = await waitForMessage(
          messages,
          (m) => m.type === "stateSync" && m.data?.currentTrack?.id === "skip1",
        );
        assert.ok(autoStart);

        // Skip — any user can do this
        ws.send(JSON.stringify({ type: "skip" }));

        const skipped = await waitForMessage(
          messages,
          (m) => m.type === "stateSync" && m.data?.currentTrack?.id === "skip2",
          3000,
        );
        assert.ok(skipped, "Should advance to skip2");
        assert.equal(skipped.data.isPlaying, true);
      } finally {
        ws.close();
      }
    });
  });

  // ----- Add to Queue + Auto-Start -----

  describe("addToQueue + Auto-Start", () => {
    it("auto-starts playback when first track is added to idle station", async () => {
      const token = await getToken(PORT, "autostart_user", "AutoStart");
      const { ws, messages } = await connectWS(PORT, token, "station-101");

      try {
        await waitForMessage(messages, (m) => m.type === "stateSync");

        ws.send(JSON.stringify({
          type: "addToQueue",
          data: { track: { id: "first", name: "First Song", durationMs: 60000 }, nonce: "auto-n1" },
        }));

        const playing = await waitForMessage(
          messages,
          (m) => m.type === "stateSync" && m.data?.currentTrack?.id === "first" && m.data?.isPlaying === true,
          3000,
        );
        assert.ok(playing, "Station should auto-start playing the first track");
      } finally {
        ws.close();
      }
    });

    it("deduplicates addToQueue with same nonce", async () => {
      const token = await getToken(PORT, "nonce_user", "NonceUser");
      const { ws, messages } = await connectWS(PORT, token, "station-93");

      try {
        await waitForMessage(messages, (m) => m.type === "stateSync");

        const track = { id: "nonce_track", name: "Nonce Song", durationMs: 180000 };
        const nonce = "unique-nonce-456";

        ws.send(JSON.stringify({ type: "addToQueue", data: { track, nonce } }));
        await waitForMessage(messages, (m) => m.type === "queueUpdate");

        const countBefore = messages.filter((m) => m.type === "queueUpdate").length;
        ws.send(JSON.stringify({ type: "addToQueue", data: { track, nonce } }));

        await new Promise((r) => setTimeout(r, 500));
        const countAfter = messages.filter((m) => m.type === "queueUpdate").length;
        assert.equal(countAfter, countBefore, "Duplicate nonce should not produce another queueUpdate");
      } finally {
        ws.close();
      }
    });
  });

  // ----- Autonomous Queue Advancement -----

  describe("Autonomous Queue Advancement", () => {
    it("advances queue when track duration elapses", async () => {
      const token = await getToken(PORT, "advance_user", "AdvUser");
      const { ws, messages } = await connectWS(PORT, token, "station-88");

      try {
        await waitForMessage(messages, (m) => m.type === "stateSync");

        // Add two tracks — first will auto-start, second stays in queue
        ws.send(JSON.stringify({
          type: "addToQueue",
          data: { track: { id: "adv1", name: "Adv 1", durationMs: 1500 }, nonce: "adv-n1" },
        }));
        ws.send(JSON.stringify({
          type: "addToQueue",
          data: { track: { id: "adv2", name: "Adv 2", durationMs: 3000 }, nonce: "adv-n2" },
        }));

        // Wait for auto-start of first track
        await waitForMessage(
          messages,
          (m) => m.type === "stateSync" && m.data?.currentTrack?.id === "adv1",
        );

        // Wait for automatic advancement to track 2 (~1.5s)
        const advanceMsg = await waitForMessage(
          messages,
          (m) => m.type === "stateSync" && m.data?.currentTrack?.id === "adv2",
          4000,
        );
        assert.ok(advanceMsg, "Should advance to adv2");
        assert.equal(advanceMsg.data.isPlaying, true);
      } finally {
        ws.close();
      }
    });
  });

  // ----- Queue Looping -----

  describe("Queue Looping", () => {
    it("loops back through history when queue exhausts", async () => {
      const token = await getToken(PORT, "loop_user", "LoopUser");
      const { ws, messages } = await connectWS(PORT, token, "station-97");

      try {
        await waitForMessage(messages, (m) => m.type === "stateSync");

        // Add two short tracks
        ws.send(JSON.stringify({
          type: "addToQueue",
          data: { track: { id: "loop1", name: "Loop 1", durationMs: 1000 }, nonce: "loop-n1" },
        }));
        ws.send(JSON.stringify({
          type: "addToQueue",
          data: { track: { id: "loop2", name: "Loop 2", durationMs: 1000 }, nonce: "loop-n2" },
        }));

        // Wait for loop1 to start
        await waitForMessage(
          messages,
          (m) => m.type === "stateSync" && m.data?.currentTrack?.id === "loop1",
        );

        // Wait for loop2
        await waitForMessage(
          messages,
          (m) => m.type === "stateSync" && m.data?.currentTrack?.id === "loop2",
          4000,
        );

        // Wait for loop back to loop1 (from history)
        const looped = await waitForMessage(
          messages,
          (m) => m.type === "stateSync" && m.data?.currentTrack?.id === "loop1" && m.data?.epoch > 2,
          4000,
        );
        assert.ok(looped, "Should loop back to loop1 from history");
        assert.equal(looped.data.isPlaying, true);
      } finally {
        ws.close();
      }
    });
  });

  // ----- Station Persistence -----

  describe("Station Persistence", () => {
    it("stations are never destroyed when all listeners leave", async () => {
      const token = await getToken(PORT, "persist_user", "PersistUser");
      const { ws, messages } = await connectWS(PORT, token, "station-88");

      try {
        await waitForMessage(messages, (m) => m.type === "stateSync");
      } finally {
        ws.close();
      }

      // Wait a moment, then verify station still exists
      await new Promise((r) => setTimeout(r, 500));

      const res = await request(PORT, "GET", "/stations/station-88", {
        headers: { Authorization: `Bearer ${token}` },
      });
      assert.equal(res.statusCode, 200);
      assert.equal(res.body.id, "station-88");
    });
  });

  // ----- Admin Endpoint -----

  describe("GET /admin/stations", () => {
    it("returns all stations with details", async () => {
      const res = await request(PORT, "GET", "/admin/stations");
      assert.equal(res.statusCode, 200);
      assert.equal(res.body.stations.length, 5);
      assert.ok(res.body.serverTime);

      const station = res.body.stations[0];
      assert.ok(station.id);
      assert.ok(station.name);
      assert.ok(Array.isArray(station.members));
    });
  });
});
