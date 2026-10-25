// GET /v1/ideas/local?cell=<geohash>&day=<YYYY-MM-DD>
//
// Anonymous, public, cached. The answer depends on the cell and the day and nothing else, so
// everyone in a neighborhood shares one cached response and the Worker never learns who asked.
// No database, no per-user state, no model in the request path: a shard of places from R2, a
// seeded pick, and the edge cache.

import { generate } from './ideas.js';
import { bounds, encode, isValidCell } from './geohash.js';

/** Shards are four-character cells (about 39 km by 20 km), since ideas reach twenty miles. */
const SHARD_PRECISION = 4;
/** Degrees of padding around the cell: twenty miles, give or take the latitude. */
const PADDING_DEGREES = 0.3;
/** How far the caller's date may be from the server's, in days. Covers every time zone. */
const DAY_TOLERANCE = 2;

const HEADERS = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'public, max-age=86400, s-maxage=86400',
  'x-content-type-options': 'nosniff',
};

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (request.method !== 'GET' || url.pathname !== '/v1/ideas/local') {
      return problem('not_found', 404);
    }
    const cell = (url.searchParams.get('cell') || '').toLowerCase();
    const day = url.searchParams.get('day') || '';
    if (!isValidCell(cell)) return problem('invalid_cell', 400);
    if (!isPlausibleDay(day, new Date())) return problem('invalid_day', 400);
    if (isSunday(day)) return problem('sunday_closed', 423, 'Sundays are for posting, not for looking around.');

    // One cached answer per (cell, day). Nothing about the caller is part of the key.
    const key = new Request(`${url.origin}/v1/ideas/local?cell=${cell}&day=${day}`, { method: 'GET' });
    const cached = await caches.default.match(key);
    if (cached) return cached;

    const places = await loadPlaces(cell, env);
    const body = JSON.stringify(generate(cell, day, places));
    const response = new Response(body, { status: 200, headers: HEADERS });
    ctx.waitUntil(caches.default.put(key, response.clone()));
    return response;
  },
};

/** The cell's own shard plus every shard the padded box touches, at most five. */
export function shardsFor(cell) {
  const b = bounds(cell);
  const corners = [
    [b.latLow - PADDING_DEGREES, b.lonLow - PADDING_DEGREES],
    [b.latLow - PADDING_DEGREES, b.lonHigh + PADDING_DEGREES],
    [b.latHigh + PADDING_DEGREES, b.lonLow - PADDING_DEGREES],
    [b.latHigh + PADDING_DEGREES, b.lonHigh + PADDING_DEGREES],
  ];
  const own = cell.slice(0, SHARD_PRECISION);
  return [...new Set([own, ...corners.map(([lat, lon]) => encode(lat, lon, SHARD_PRECISION))])];
}

async function loadPlaces(cell, env) {
  const lists = await Promise.all(
    shardsFor(cell).map(async (shard) => {
      const object = await env.PLACES.get(`places/${shard}.json`);
      return object ? object.json() : [];
    }),
  );
  return lists.flat();
}

export function isPlausibleDay(day, now) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return false;
  const parsed = new Date(`${day}T12:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== day) return false;
  const distance = Math.abs(parsed.getTime() - now.getTime()) / 86400000;
  return distance <= DAY_TOLERANCE + 0.5;
}

export function isSunday(day) {
  return new Date(`${day}T12:00:00Z`).getUTCDay() === 0;
}

function problem(code, status, message) {
  return new Response(JSON.stringify({ error: { code, message: message ?? code } }), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });
}
