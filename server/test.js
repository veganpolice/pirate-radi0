import { describe, it, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { WebSocket } from "ws";

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

// ---------------------------------------------------------------------------
// WebSocket Tests
// ---------------------------------------------------------------------------

/**
 * Connect a WebSocket to the server and wait for the first message (stateSync).
 * Returns { ws, firstMessage }.
 */
function connectWebSocket(port, token, sessionId) {
  return new Promise((resolve, reject) => {
    const url = `ws://127.0.0.1:${port}/?token=${encodeURIComponent(token)}&sessionId=${encodeURIComponent(sessionId)}`;
    const ws = new WebSocket(url);
    const timeout = setTimeout(() => {
      ws.close();
      reject(new Error("WebSocket connection timed out"));
    }, 5000);

    ws.on("message", (raw) => {
      clearTimeout(timeout);
      const msg = JSON.parse(raw.toString());
      resolve({ ws, firstMessage: msg });
    });

    ws.on("error", (err) => {
      clearTimeout(timeout);
      reject(err);
    });
  });
}

/**
 * Wait for the next message on a WebSocket, with timeout.
 */
function waitForMessage(ws, timeoutMs = 3000) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Timed out waiting for message")), timeoutMs);
    ws.once("message", (raw) => {
      clearTimeout(timeout);
      resolve(JSON.parse(raw.toString()));
    });
  });
}

describe("WebSocket Sync Protocol", () => {
  before(async () => {
    // Reuse the server from the API tests (already running)
    // If running standalone, start a new one
    if (!serverProcess) {
      await startServer();
    }
  });

  after(() => {
    stopServer();
  });

  it("sends stateSync on WebSocket connect", async () => {
    const token = await getToken(PORT, "ws_dj_1");
    const session = await createSession(PORT, token);

    const { ws, firstMessage } = await connectWebSocket(PORT, token, session.id);
    try {
      assert.equal(firstMessage.type, "stateSync");
      assert.equal(firstMessage.data.id, session.id);
      assert.equal(firstMessage.data.djUserId, "ws_dj_1");
      assert.equal(firstMessage.data.isPlaying, false);
      assert.ok(Array.isArray(firstMessage.data.members));
      assert.ok(Array.isArray(firstMessage.data.queue));
    } finally {
      ws.close();
    }
  });

  it("broadcasts memberJoined when a listener connects", async () => {
    const djToken = await getToken(PORT, "ws_dj_2");
    const session = await createSession(PORT, djToken);

    const { ws: djWs } = await connectWebSocket(PORT, djToken, session.id);
    try {
      const listenerToken = await getToken(PORT, "ws_listener_2");

      // Set up the listener for memberJoined BEFORE the listener connects
      const memberJoinedPromise = waitForMessage(djWs);

      const { ws: listenerWs } = await connectWebSocket(PORT, listenerToken, session.id);
      try {
        const msg = await memberJoinedPromise;
        assert.equal(msg.type, "memberJoined");
        assert.equal(msg.data.userId, "ws_listener_2");
      } finally {
        listenerWs.close();
      }
    } finally {
      djWs.close();
    }
  });

  it("relays playPrepare from DJ to listeners", async () => {
    const djToken = await getToken(PORT, "ws_dj_3");
    const session = await createSession(PORT, djToken);

    const { ws: djWs } = await connectWebSocket(PORT, djToken, session.id);
    try {
      const listenerToken = await getToken(PORT, "ws_listener_3");
      const { ws: listenerWs } = await connectWebSocket(PORT, listenerToken, session.id);
      try {
        // Wait for memberJoined on DJ side
        await waitForMessage(djWs);

        // DJ sends playPrepare
        const preparePromise = waitForMessage(listenerWs);
        djWs.send(JSON.stringify({
          type: "playPrepare",
          data: { trackId: "track-xyz", track: { id: "track-xyz", name: "Test" } },
        }));

        const msg = await preparePromise;
        assert.equal(msg.type, "playPrepare");
        assert.equal(msg.data.trackId, "track-xyz");
        assert.ok(msg.epoch > 0); // epoch incremented
        assert.ok(msg.seq > 0);
      } finally {
        listenerWs.close();
      }
    } finally {
      djWs.close();
    }
  });

  it("ignores playPrepare from non-DJ", async () => {
    const djToken = await getToken(PORT, "ws_dj_4");
    const session = await createSession(PORT, djToken);

    const { ws: djWs } = await connectWebSocket(PORT, djToken, session.id);
    try {
      const listenerToken = await getToken(PORT, "ws_listener_4");
      const { ws: listenerWs } = await connectWebSocket(PORT, listenerToken, session.id);
      try {
        await waitForMessage(djWs); // memberJoined

        // Listener (non-DJ) sends playPrepare — should be ignored
        listenerWs.send(JSON.stringify({
          type: "playPrepare",
          data: { trackId: "unauthorized" },
        }));

        // DJ should not receive the message. Wait briefly and check.
        const result = await Promise.race([
          waitForMessage(djWs, 500).then(() => "received").catch(() => "timeout"),
          new Promise((resolve) => setTimeout(() => resolve("timeout"), 500)),
        ]);
        assert.equal(result, "timeout", "Non-DJ playPrepare should be silently ignored");
      } finally {
        listenerWs.close();
      }
    } finally {
      djWs.close();
    }
  });

  it("broadcasts memberLeft when listener disconnects", async () => {
    const djToken = await getToken(PORT, "ws_dj_5");
    const session = await createSession(PORT, djToken);

    const { ws: djWs } = await connectWebSocket(PORT, djToken, session.id);
    try {
      const listenerToken = await getToken(PORT, "ws_listener_5");
      const { ws: listenerWs } = await connectWebSocket(PORT, listenerToken, session.id);

      await waitForMessage(djWs); // memberJoined

      const memberLeftPromise = waitForMessage(djWs);
      listenerWs.close();

      const msg = await memberLeftPromise;
      assert.equal(msg.type, "memberLeft");
      assert.equal(msg.data.userId, "ws_listener_5");
    } finally {
      djWs.close();
    }
  });

  it("promotes new DJ when DJ disconnects", async () => {
    const djToken = await getToken(PORT, "ws_dj_6");
    const session = await createSession(PORT, djToken);

    const { ws: djWs } = await connectWebSocket(PORT, djToken, session.id);

    const listenerToken = await getToken(PORT, "ws_listener_6");
    const { ws: listenerWs } = await connectWebSocket(PORT, listenerToken, session.id);
    try {
      await waitForMessage(djWs); // memberJoined

      // Collect messages from listener after DJ disconnects
      const messages = [];
      const collected = new Promise((resolve) => {
        const timeout = setTimeout(() => resolve(messages), 2000);
        listenerWs.on("message", (raw) => {
          messages.push(JSON.parse(raw.toString()));
          // Once we see stateSync, we have what we need
          if (messages.some((m) => m.type === "stateSync")) {
            clearTimeout(timeout);
            resolve(messages);
          }
        });
      });

      djWs.close();
      await collected;

      const stateSync = messages.find((m) => m.type === "stateSync");
      assert.ok(stateSync, "Expected stateSync after DJ disconnect");
      assert.equal(stateSync.data.djUserId, "ws_listener_6");
    } finally {
      listenerWs.close();
    }
  });

  it("responds to ping with pong containing server time", async () => {
    const token = await getToken(PORT, "ws_ping_user");
    const session = await createSession(PORT, token);

    const { ws } = await connectWebSocket(PORT, token, session.id);
    try {
      const pongPromise = waitForMessage(ws);
      ws.send(JSON.stringify({
        type: "ping",
        data: { clientSendTime: 1700000000000 },
      }));

      const msg = await pongPromise;
      assert.equal(msg.type, "pong");
      assert.equal(msg.data.clientSendTime, 1700000000000);
      assert.equal(typeof msg.data.serverTime, "number");
      assert.ok(msg.data.serverTime > 0);
    } finally {
      ws.close();
    }
  });

  it("relays playCommit from DJ to listeners", async () => {
    const djToken = await getToken(PORT, "ws_dj_7");
    const session = await createSession(PORT, djToken);

    const { ws: djWs } = await connectWebSocket(PORT, djToken, session.id);
    try {
      const listenerToken = await getToken(PORT, "ws_listener_7");
      const { ws: listenerWs } = await connectWebSocket(PORT, listenerToken, session.id);
      try {
        await waitForMessage(djWs); // memberJoined

        // DJ sends playPrepare first
        djWs.send(JSON.stringify({
          type: "playPrepare",
          data: { trackId: "track-commit", track: { id: "track-commit" } },
        }));
        await waitForMessage(listenerWs); // playPrepare

        // DJ sends playCommit
        const commitPromise = waitForMessage(listenerWs);
        djWs.send(JSON.stringify({
          type: "playCommit",
          data: { ntpTimestamp: 1700000001500, positionMs: 0 },
        }));

        const msg = await commitPromise;
        assert.equal(msg.type, "playCommit");
        assert.ok(msg.epoch > 0);
        assert.ok(msg.seq > 0);
      } finally {
        listenerWs.close();
      }
    } finally {
      djWs.close();
    }
  });

  it("relays pause from DJ to listeners", async () => {
    const djToken = await getToken(PORT, "ws_dj_8");
    const session = await createSession(PORT, djToken);

    const { ws: djWs } = await connectWebSocket(PORT, djToken, session.id);
    try {
      const listenerToken = await getToken(PORT, "ws_listener_8");
      const { ws: listenerWs } = await connectWebSocket(PORT, listenerToken, session.id);
      try {
        await waitForMessage(djWs); // memberJoined

        const pausePromise = waitForMessage(listenerWs);
        djWs.send(JSON.stringify({ type: "pause", data: {} }));

        const msg = await pausePromise;
        assert.equal(msg.type, "pause");
        assert.equal(typeof msg.data.positionMs, "number");
        assert.equal(typeof msg.data.ntpTimestamp, "number");
      } finally {
        listenerWs.close();
      }
    } finally {
      djWs.close();
    }
  });
});
