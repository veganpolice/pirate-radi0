CREATE TABLE IF NOT EXISTS stations (
  user_id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  frequency INTEGER NOT NULL UNIQUE CHECK(frequency >= 881 AND frequency <= 1079 AND frequency % 2 = 1),
  tracks_json TEXT NOT NULL DEFAULT '[]',
  snapshot_track_index INTEGER NOT NULL DEFAULT 0 CHECK(snapshot_track_index >= 0),
  snapshot_elapsed_ms INTEGER NOT NULL DEFAULT 0 CHECK(snapshot_elapsed_ms >= 0),
  snapshot_timestamp INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL DEFAULT (unixepoch('now') * 1000)
);
