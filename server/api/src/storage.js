// Where photo bytes live. An R2 bucket bound as PHOTOS (10 GB free). Without one, the D1
// database itself, in 256 KB base64 chunks: no card on file needed, but a free database holds
// 500 MB, a few hundred photos, so it is for trying the server out. Turning R2 on later loses
// nothing: reads fall back to D1, and deletes clear both.

const CHUNK = 256 * 1024;

function toBase64(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

function fromBase64(text) {
  const s = atob(text);
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

function d1Storage(db) {
  return {
    async put(key, bytes) {
      const statements = [db.prepare('DELETE FROM blob_chunks WHERE key = ?').bind(key)];
      for (let i = 0, idx = 0; i < bytes.length; i += CHUNK, idx++) {
        statements.push(db.prepare('INSERT INTO blob_chunks (key, idx, data) VALUES (?, ?, ?)')
          .bind(key, idx, toBase64(bytes.subarray(i, i + CHUNK))));
      }
      await db.batch(statements);
    },
    async get(key) {
      const { results } = await db.prepare('SELECT data FROM blob_chunks WHERE key = ? ORDER BY idx').bind(key).all();
      if (!results.length) return null;
      const parts = results.map((r) => fromBase64(r.data));
      const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
      let offset = 0;
      for (const p of parts) { out.set(p, offset); offset += p.length; }
      return out;
    },
    /** One query for any number of keys. */
    async deleteMany(keys) {
      if (!keys.length) return;
      await db.prepare('DELETE FROM blob_chunks WHERE key IN (SELECT value FROM json_each(?))').bind(JSON.stringify(keys)).run();
    },
  };
}

function r2Storage(bucket, fallback) {
  return {
    async put(key, bytes) {
      await bucket.put(key, bytes, { httpMetadata: { contentType: 'image/jpeg' } });
    },
    async get(key) {
      const object = await bucket.get(key);
      return object ? new Uint8Array(await object.arrayBuffer()) : fallback.get(key);
    },
    async deleteMany(keys) {
      // R2 deletes up to 1,000 keys per call, and deletes are free.
      for (let i = 0; i < keys.length; i += 1000) await bucket.delete(keys.slice(i, i + 1000));
      await fallback.deleteMany(keys);
    },
  };
}

export function storage(env) {
  const d1 = d1Storage(env.DB);
  return env.PHOTOS ? r2Storage(env.PHOTOS, d1) : d1;
}
