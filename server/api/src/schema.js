// The whole database. Applied on first use (every statement is IF NOT EXISTS), so a fresh
// D1 database needs no separate migration step. Bump SCHEMA_VERSION when adding statements.

// 2: the admins and used_nonces tables.
// 3: a caption on each photo (COLUMNS).
export const SCHEMA_VERSION = '3';

export const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS config (key TEXT PRIMARY KEY, value TEXT NOT NULL)`,
  // Who may use Sunday any day, to test. Filled by hand from the Cloudflare side, never by the API.
  `CREATE TABLE IF NOT EXISTS admins (user_id TEXT PRIMARY KEY)`,
  `CREATE TABLE IF NOT EXISTS users (
     id TEXT PRIMARY KEY, apple_sub TEXT UNIQUE, username TEXT NOT NULL UNIQUE,
     name TEXT NOT NULL DEFAULT '', bio TEXT NOT NULL DEFAULT '', avatar_key TEXT,
     is_public INTEGER NOT NULL DEFAULT 0, timezone TEXT NOT NULL DEFAULT 'UTC',
     settings TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS refresh_tokens (
     hash TEXT PRIMARY KEY, user_id TEXT NOT NULL, family TEXT NOT NULL,
     expires_at INTEGER NOT NULL, used INTEGER NOT NULL DEFAULT 0, revoked INTEGER NOT NULL DEFAULT 0)`,
  `CREATE INDEX IF NOT EXISTS refresh_tokens_family ON refresh_tokens (family)`,
  // Sign in with Apple nonces already used, so a captured token and nonce cannot sign in twice.
  `CREATE TABLE IF NOT EXISTS used_nonces (hash TEXT PRIMARY KEY, expires_at INTEGER NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS follows (
     follower_id TEXT NOT NULL, followee_id TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL,
     PRIMARY KEY (follower_id, followee_id))`,
  `CREATE INDEX IF NOT EXISTS follows_followee ON follows (followee_id, status)`,
  `CREATE TABLE IF NOT EXISTS blocks (blocker_id TEXT NOT NULL, blocked_id TEXT NOT NULL, PRIMARY KEY (blocker_id, blocked_id))`,
  `CREATE INDEX IF NOT EXISTS blocks_blocked ON blocks (blocked_id)`,
  `CREATE TABLE IF NOT EXISTS uploads (
     id TEXT PRIMARY KEY, user_id TEXT NOT NULL, object_key TEXT NOT NULL, byte_size INTEGER NOT NULL,
     width INTEGER, height INTEGER, expires_at INTEGER NOT NULL, uploaded INTEGER NOT NULL DEFAULT 0)`,
  `CREATE INDEX IF NOT EXISTS uploads_user ON uploads (user_id, expires_at)`,
  `CREATE TABLE IF NOT EXISTS dumps (
     id TEXT PRIMARY KEY, author_id TEXT NOT NULL, week_start TEXT NOT NULL, caption TEXT NOT NULL DEFAULT '',
     comments_enabled INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
     UNIQUE (author_id, week_start))`,
  `CREATE INDEX IF NOT EXISTS dumps_created ON dumps (created_at)`,
  `CREATE TABLE IF NOT EXISTS photos (
     id TEXT PRIMARY KEY, dump_id TEXT NOT NULL, ord INTEGER NOT NULL, object_key TEXT NOT NULL,
     width INTEGER NOT NULL, height INTEGER NOT NULL, alt_text TEXT, upload_id TEXT UNIQUE, caption TEXT)`,
  `CREATE INDEX IF NOT EXISTS photos_dump ON photos (dump_id)`,
  `CREATE TABLE IF NOT EXISTS tags (
     id TEXT PRIMARY KEY, photo_id TEXT NOT NULL, tagger_id TEXT NOT NULL, tagged_user_id TEXT NOT NULL,
     status TEXT NOT NULL, responded_at TEXT, created_at TEXT NOT NULL, UNIQUE (photo_id, tagged_user_id))`,
  `CREATE INDEX IF NOT EXISTS tags_tagged ON tags (tagged_user_id, status)`,
  `CREATE TABLE IF NOT EXISTS likes (dump_id TEXT NOT NULL, user_id TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY (dump_id, user_id))`,
  `CREATE TABLE IF NOT EXISTS comments (
     id TEXT PRIMARY KEY, dump_id TEXT NOT NULL, author_id TEXT NOT NULL, body TEXT NOT NULL,
     created_at TEXT NOT NULL, edited_at TEXT)`,
  `CREATE INDEX IF NOT EXISTS comments_dump ON comments (dump_id, created_at)`,
  `CREATE TABLE IF NOT EXISTS comment_likes (comment_id TEXT NOT NULL, user_id TEXT NOT NULL, PRIMARY KEY (comment_id, user_id))`,
  `CREATE TABLE IF NOT EXISTS suggestions_done (
     user_id TEXT NOT NULL, suggestion_id TEXT NOT NULL, done_on TEXT NOT NULL, PRIMARY KEY (user_id, suggestion_id))`,
  `CREATE TABLE IF NOT EXISTS reports (
     id TEXT PRIMARY KEY, reporter_id TEXT NOT NULL, target_type TEXT NOT NULL, target_id TEXT NOT NULL,
     reason TEXT NOT NULL, note TEXT, created_at TEXT NOT NULL)`,
  // Photos live here, in chunks, unless an R2 bucket is bound as PHOTOS.
  `CREATE TABLE IF NOT EXISTS blob_chunks (key TEXT NOT NULL, idx INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY (key, idx))`,
];

/** Columns added to tables that may already exist. A fresh database gets them from SCHEMA;
 * an older one gets them here, each added only when missing, since adding one twice fails. */
export const COLUMNS = [
  { table: 'photos', column: 'caption', sql: 'ALTER TABLE photos ADD COLUMN caption TEXT' },
];

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
