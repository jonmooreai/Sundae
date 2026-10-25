#!/usr/bin/env node
// Groups places into one JSON file per four-character geohash cell, ready for R2.
//
//   node scripts/build-shards.mjs places.ndjson out/
//   for f in out/places/*.json; do npx wrangler r2 object put "sundae-places/places/$(basename "$f")" --file "$f"; done
//
// Input: NDJSON lines {id, name, category, lat, lon} (see places.sql). Categories are mapped
// onto the themes in src/ideas.js; anything unmapped is dropped.

import { createReadStream } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';
import { createInterface } from 'node:readline';
import path from 'node:path';
import { encode } from '../src/geohash.js';
import { THEMES } from '../src/ideas.js';

const CATEGORY_MAP = {
  cafe: 'cafe', coffee_shop: 'cafe', tea_room: 'cafe',
  bakery: 'bakery', patisserie: 'bakery',
  park: 'park', dog_park: 'park', playground: 'park', plaza: 'park', public_plaza: 'park',
  scenic_lookout: 'viewpoint', scenic_point: 'viewpoint', observation_deck: 'viewpoint', lookout: 'viewpoint',
  library: 'library', public_library: 'library',
  bookstore: 'bookstore', used_bookstore: 'bookstore', comic_book_store: 'bookstore',
  farmers_market: 'market', public_market: 'market', market: 'market',
  museum: 'museum', art_museum: 'museum', history_museum: 'museum', science_museum: 'museum',
  art_gallery: 'gallery', gallery: 'gallery',
  botanical_garden: 'garden', community_garden: 'garden', garden: 'garden',
  hiking_trail: 'trail', trail: 'trail', trailhead: 'trail',
  beach: 'waterfront', pier: 'waterfront', boardwalk: 'waterfront', waterfront: 'waterfront', promenade: 'waterfront', marina: 'waterfront',
  diner: 'diner', breakfast_restaurant: 'diner',
  record_store: 'record_store', music_store: 'record_store', vinyl_record_store: 'record_store',
  ice_cream_shop: 'ice_cream', gelato_shop: 'ice_cream',
};

const [input, outDir = 'out'] = process.argv.slice(2);
if (!input) {
  console.error('usage: build-shards.mjs <places.ndjson> [outDir]');
  process.exit(1);
}

const shards = new Map();
let read = 0, kept = 0;
for await (const line of createInterface({ input: createReadStream(input), crlfDelay: Infinity })) {
  if (!line.trim()) continue;
  read++;
  let row;
  try { row = JSON.parse(line); } catch { continue; }
  const category = CATEGORY_MAP[row.category];
  if (!category || !THEMES[category] || !row.name || !Number.isFinite(row.lat) || !Number.isFinite(row.lon)) continue;
  const shard = encode(row.lat, row.lon, 4);
  if (!shards.has(shard)) shards.set(shard, []);
  shards.get(shard).push({
    id: String(row.id),
    name: String(row.name).slice(0, 80),
    category,
    lat: Math.round(row.lat * 1e5) / 1e5,
    lon: Math.round(row.lon * 1e5) / 1e5,
  });
  kept++;
}

const dir = path.join(outDir, 'places');
await mkdir(dir, { recursive: true });
let bytes = 0;
for (const [shard, places] of shards) {
  const body = JSON.stringify(places);
  bytes += body.length;
  await writeFile(path.join(dir, `${shard}.json`), body);
}
console.log(`${read} places read, ${kept} kept, ${shards.size} shards, ${(bytes / 1e6).toFixed(1)} MB`);
