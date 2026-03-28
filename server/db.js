import Database from "better-sqlite3";
import { existsSync, mkdirSync } from "fs";
import { dirname } from "path";

// --- Station Definitions ---

export const STATIONS = [
  { id: "station-88",  name: "88.🏴‍☠️", frequency: 88.1 },
  { id: "station-93",  name: "93.🔥",   frequency: 93.3 },
  { id: "station-97",  name: "97.🌊",   frequency: 97.7 },
  { id: "station-101", name: "101.💀",   frequency: 101.1 },
  { id: "station-107", name: "107.👑",   frequency: 107.9 },
];

// --- Database Setup ---

const DB_PATH = process.env.DB_PATH || (process.env.NODE_ENV === "test" ? ":memory:" : "/data/pirate-radio.db");

let db;

export function initDB() {
  if (DB_PATH !== ":memory:") {
    const dir = dirname(DB_PATH);
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  }

  db = new Database(DB_PATH);
  db.pragma("journal_mode = WAL");

  db.exec(`
    CREATE TABLE IF NOT EXISTS stations (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      frequency REAL NOT NULL,
      current_track_json TEXT,
      is_playing INTEGER DEFAULT 0,
      position_ms REAL DEFAULT 0,
      position_timestamp INTEGER DEFAULT 0,
      epoch INTEGER DEFAULT 0,
      sequence INTEGER DEFAULT 0,
      queue_json TEXT DEFAULT '[]',
      history_json TEXT DEFAULT '[]'
    )
  `);

  return db;
}

export function getDB() {
  return db;
}

// --- Station Persistence ---

const UPSERT_SQL = `
  INSERT INTO stations (id, name, frequency, current_track_json, is_playing, position_ms, position_timestamp, epoch, sequence, queue_json, history_json)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    current_track_json = excluded.current_track_json,
    is_playing = excluded.is_playing,
    position_ms = excluded.position_ms,
    position_timestamp = excluded.position_timestamp,
    epoch = excluded.epoch,
    sequence = excluded.sequence,
    queue_json = excluded.queue_json,
    history_json = excluded.history_json
`;

export function persistStation(station) {
  if (!db) return;
  db.prepare(UPSERT_SQL).run(
    station.id,
    station.name,
    station.frequency,
    station.currentTrack ? JSON.stringify(station.currentTrack) : null,
    station.isPlaying ? 1 : 0,
    station.positionMs,
    station.positionTimestamp,
    station.epoch,
    station.sequence,
    JSON.stringify(station.queue),
    JSON.stringify(station.history),
  );
}

export function loadStations() {
  if (!db) return [];

  const rows = db.prepare("SELECT * FROM stations").all();
  return rows.map((row) => {
    let currentTrack = null;
    let queue = [];
    let history = [];
    try { currentTrack = row.current_track_json ? JSON.parse(row.current_track_json) : null; } catch { /* corrupted, reset */ }
    try { queue = JSON.parse(row.queue_json); } catch { /* corrupted, reset */ }
    try { history = JSON.parse(row.history_json); } catch { /* corrupted, reset */ }
    if (!Array.isArray(queue)) queue = [];
    if (!Array.isArray(history)) history = [];

    return {
      id: row.id,
      name: row.name,
      frequency: row.frequency,
      currentTrack,
      isPlaying: row.is_playing === 1,
      positionMs: row.position_ms,
      positionTimestamp: row.position_timestamp,
      epoch: row.epoch,
      sequence: row.sequence,
      queue,
      history,
    };
  });
}

export function closeDB() {
  if (db) {
    db.close();
    db = null;
  }
}
