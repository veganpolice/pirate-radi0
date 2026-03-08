import Database from "better-sqlite3";
import { readFileSync } from "fs";
import { join } from "path";

export function createDatabase(dbPath) {
  const db = new Database(dbPath);
  db.pragma("journal_mode = WAL");
  db.pragma("synchronous = NORMAL");
  db.pragma("foreign_keys = ON");
  db.exec(
    readFileSync(
      join(import.meta.dirname, "migrations/001-initial-schema.sql"),
      "utf8"
    )
  );
  return db;
}
