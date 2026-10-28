// The whole database. Applied on first use (every statement is safe to run again), so a fresh D1
// database needs no separate migration step. Bump SCHEMA_VERSION whenever SCHEMA or COLUMNS
// change, and say what changed on the line above it.

// 1: accounts, sessions, Sign in with Apple nonces, admins, notes.
export const SCHEMA_VERSION = '1';

export const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS config (key TEXT PRIMARY KEY, value TEXT NOT NULL)`,
  // Who is an admin, by the private id Sign in with Apple gives their Apple Account, so it follows
  // the person through a new username or a deleted and remade account. Filled by hand from the
  // Cloudflare side (docs/SETUP.md), never by the API.
  `CREATE TABLE IF NOT EXISTS admin_apple_ids (apple_sub TEXT PRIMARY KEY)`,
  `CREATE TABLE IF NOT EXISTS users (
     id TEXT PRIMARY KEY, apple_sub TEXT UNIQUE, username TEXT NOT NULL UNIQUE,
     name TEXT NOT NULL DEFAULT '', timezone TEXT NOT NULL DEFAULT 'UTC', created_at TEXT NOT NULL)`,
  // Refresh tokens are kept only as SHA-256 hashes. A family is one sign-in on one device.
  `CREATE TABLE IF NOT EXISTS refresh_tokens (
     hash TEXT PRIMARY KEY, user_id TEXT NOT NULL, family TEXT NOT NULL,
     expires_at INTEGER NOT NULL, used INTEGER NOT NULL DEFAULT 0, revoked INTEGER NOT NULL DEFAULT 0)`,
  `CREATE INDEX IF NOT EXISTS refresh_tokens_family ON refresh_tokens (family)`,
  `CREATE INDEX IF NOT EXISTS refresh_tokens_user ON refresh_tokens (user_id)`,
  // Sign in with Apple nonces already used, so a captured token and nonce cannot sign in twice.
  `CREATE TABLE IF NOT EXISTS used_nonces (hash TEXT PRIMARY KEY, expires_at INTEGER NOT NULL)`,
  // The example data: each person's own notes. Replace with the app's real tables.
  `CREATE TABLE IF NOT EXISTS notes (
     id TEXT PRIMARY KEY, user_id TEXT NOT NULL, text TEXT NOT NULL, created_at TEXT NOT NULL)`,
  `CREATE INDEX IF NOT EXISTS notes_user ON notes (user_id, created_at)`,
];

/** Columns added to tables that may already exist. A fresh database gets them from SCHEMA; an
 * older one gets them here, each added only when missing, since adding one twice fails.
 * Example: { table: 'notes', column: 'pinned', sql: 'ALTER TABLE notes ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0' } */
export const COLUMNS = [];

let ready = null;

/** Creates any missing tables once per isolate. One read on every later cold start. */
export function ensureSchema(db) {
  ready ??= (async () => {
    try {
      const row = await db.prepare(`SELECT value FROM config WHERE key = 'schema_version'`).first();
      if (row?.value === SCHEMA_VERSION) return;
    } catch {
      // No config table yet: a fresh database.
    }
    await db.batch(SCHEMA.map((sql) => db.prepare(sql)));
    for (const { table, column, sql } of COLUMNS) {
      const { results } = await db.prepare(`PRAGMA table_info(${table})`).all();
      if (!results.some((info) => info.name === column)) await db.prepare(sql).run();
    }
    await db.prepare(`INSERT INTO config (key, value) VALUES ('schema_version', ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value`)
      .bind(SCHEMA_VERSION).run();
  })().catch((error) => {
    ready = null;
    throw error;
  });
  return ready;
}

/** For tests: forget that the schema was applied. */
export function resetSchemaCache() {
  ready = null;
}
